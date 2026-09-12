"""Fixture tests for ADR 0004; no native backend installation required."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from build import configure
from build.config_model import BackendConfig
from build.grid_config import configure_grid
from build.qex_config import configure_qex, read_qexconfig
from build.quda_config import configure_quda
from build import common
from build.artifacts import IntegrityError, archive_spec, toolchain_archive
import hashlib
import io
import tarfile

ROOT = Path(__file__).resolve().parents[1]
NIM = shutil.which("nim")


class BuildContract(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="quark build ' ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.args = configure.build_parser().parse_args([])

    def test_qex_settings(self):
        (self.root / "qex/src").mkdir(parents=True)
        config = self.root / "qexconfig.nims"
        config.write_text(
            'nimcache = getCurrentDir() / "nimcache"\n'
            'cc = "mpicc"\nld = cc\ncflagsAlways = "-O2"\n'
            'ldflags = cflagsAlways & " -ldl"\nvlen = 8\n'
            'envs = @["A=a,b", "B=hash#and&", "C=it\'s spaced"]\n'
            'nimargs = @["-d:hello=a,b", "--path:/a b"]\n')
        values = read_qexconfig(config)
        self.assertEqual(values["ldflags"], "-O2 -ldl")
        self.assertEqual(values["nimcache"], str(self.root / "nimcache"))
        cfg = configure_qex(self.root, {}, self.args)
        self.assertIn("--putenv:A=a,b", cfg.nimFlags)
        self.assertIn("--putenv:B=hash#and&", cfg.nimFlags)
        self.assertIn("--putenv:C=it's spaced", cfg.nimFlags)
        self.assertIn("--path:/a b", cfg.nimFlags)
        config.write_text('cc = getEnv("CC")\n')
        with self.assertRaisesRegex(RuntimeError, "cannot resolve QEX setting cc"):
            read_qexconfig(config)

    def test_grid_flags_and_failure(self):
        script = self.root / "grid-config"
        script.touch()
        flags = ["-I/a b", "-DNAME=it's", "-O3"]
        with patch("build.grid_config.subprocess.check_output",
                   side_effect=[shlex.join(flags), "'-L/a b'", "-lGrid -lGrid", "SIMD AVX2"]):
            cfg = configure_grid(self.root, {"config": str(script)}, self.args)
        section = cfg.as_section()
        rendered = section.split("passC    = ", 1)[1].splitlines()[0]
        self.assertEqual(shlex.split(json.loads(rendered))[:3], flags)
        self.assertEqual(cfg.passL.count("-lGrid"), 2)
        with patch("build.grid_config.subprocess.check_output", side_effect=OSError):
            with self.assertRaisesRegex(RuntimeError, "failed"):
                configure_grid(self.root, {"config": str(script)}, self.args)

    def test_quda_dependency_without_cache(self):
        (self.root / "include").mkdir()
        cfg = configure_quda(self.root, {}, self.args)
        self.assertEqual(configure.choose_default(self.args, [cfg]), "")
        self.args.backend = "QUDA"
        with self.assertRaisesRegex(RuntimeError, "dependency-only"):
            configure.choose_default(self.args, [cfg])

    def test_verified_downloads_and_cached_corruption(self):
        archive = self.root / "fixture.tar.xz"
        expected = hashlib.sha256(b"archive fixture").hexdigest()
        def fetch(command):
            Path(command[command.index("-o") + 1]).write_bytes(b"archive fixture")
        with patch("build.common.archive_spec", return_value={"sha256": expected}), \
             patch("build.common.run", side_effect=fetch) as run:
            common.download("https://fixture/archive", archive)
            common.download("https://fixture/archive", archive)
            self.assertEqual(run.call_count, 1)
            archive.write_bytes(b"corrupt")
            with self.assertRaises(IntegrityError):
                common.download("https://fixture/archive", archive)
        with self.assertRaises(IntegrityError):
            archive_spec("https://unknown/archive")

    def test_toolchain_archive_matrix(self):
        for tool, version in [("nim", "2.2.8"), ("llvm", "18.1.8")]:
            for arch in ["x64", "arm64"]:
                url = toolchain_archive(tool, version, arch)
                self.assertEqual(len(archive_spec(url)["sha256"]), 64)
        self.assertTrue(toolchain_archive("llvm", "18.1.8", "x64").endswith(
            "clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz"))
        with self.assertRaises(IntegrityError):
            toolchain_archive("nim", "0.0.0", "x64")

    def test_toolchain_extraction_layouts(self):
        for arch in ("x64", "arm64"):
            layout = common.Layout(self.root / arch, "qex")
            layout.create()
            def download_fixture(url, destination):
                stem = destination.name.removesuffix(".tar.xz")
                if stem.startswith("nim-"):
                    stem = "nim-2.2.8"
                    binary = "nim"
                else:
                    binary = "clang"
                with tarfile.open(destination, "w:xz") as archive:
                    info = tarfile.TarInfo(stem + "/bin/" + binary)
                    info.size = 7
                    archive.addfile(info, io.BytesIO(b"fixture"))
            with patch("build.common.host_arch", return_value=arch), \
                 patch("build.common.download", side_effect=download_fixture):
                binary = common.install_nim(layout)
                self.assertTrue(binary.is_symlink())
                self.assertEqual(binary.resolve().parent.parent.name, "nim-2.2.8")
                llvm = common._install_prebuilt_llvm(layout)
                self.assertTrue((llvm / "bin/clang").is_file())

    def test_aliases_in_bootstrap_and_configure(self):
        alias = " QuAnTuM_EXpressions "
        self.assertEqual(configure.canonical_backend(alias), "qex")
        result = subprocess.run([str(ROOT / "bootstrap"), "--backend", alias, "--help"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--qex-repo", result.stdout)
        (self.root / "qex/src").mkdir(parents=True)
        (self.root / "qexconfig.nims").write_text('envs = @[]\nnimargs = @[]\n')
        self.args.only = [alias]
        configs = configure.collect(self.args, self.root, {
            "backends": {"qex": {"prefix": str(self.root)}}})
        self.assertEqual([cfg.name for cfg in configs], ["qex"])

    def test_manifest_and_fallback_provenance(self):
        layout = common.Layout(self.root, "qex")
        layout.create()
        def failed():
            raise RuntimeError("native build failed")
        with patch("build.common.ensure_spack"), patch("build.common.spack_link_into"):
            common.build_or_spack("qmp", failed, (), layout)
        with patch("build.common.spack_link_into") as spack:
            def corrupt():
                raise IntegrityError("corrupt archive")
            with self.assertRaises(IntegrityError):
                common.build_or_spack("qmp", corrupt, (), layout)
            spack.assert_not_called()
        source = layout.src / "qex"
        source.mkdir()
        identity = {"commit": "a" * 40, "remote": "fixture", "patch": "",
                    "submodules": "", "untracked": ""}
        with patch("build.common.source_identity", return_value=identity):
            common.write_manifest(layout, "qex", {"source": str(source)})
        common.write_manifest(layout, "grid", {"prefix": "/grid"})
        data = json.loads(layout.manifest.read_text())
        self.assertEqual(data["backends"]["qex"]["commit"], "a" * 40)
        self.assertEqual(data["backends"]["qex"]["resolutions"]["qmp"]["provider"], "spack")
        self.assertIn("grid", data["backends"])

    def test_clone_resolves_commit_and_quotes_paths(self):
        path = self.root / "source with spaces"
        with patch("build.common.run") as run, patch("build.common.capture", return_value="a" * 40):
            common.clone_repository(path, "/repo with spaces", "some-revision")
        self.assertEqual(run.call_args_list[0].args[0],
                         ["git", "clone", "--no-checkout", "/repo with spaces", str(path)])
        self.assertEqual(run.call_args_list[-1].args[0],
                         ["git", "checkout", "--detach", "FETCH_HEAD"])

    def test_local_repository_resolution(self):
        origin = self.root / "upstream"
        subprocess.run(["git", "init", "-q", str(origin)], check=True)
        subprocess.run(["git", "-C", str(origin), "-c", "user.name=Fixture",
                        "-c", "user.email=fixture@example.invalid", "commit", "-q",
                        "--allow-empty", "-m", "fixture"], check=True)
        commit = common.capture(["git", "rev-parse", "HEAD"], cwd=origin)
        source = self.root / "checkout"
        common.clone_repository(source, str(origin), commit)
        identity = common.source_identity(source)
        self.assertEqual(identity["commit"], commit)
        self.assertEqual(identity["remote"], str(origin))
        self.assertEqual(identity["patch"], "")

    @unittest.skipUnless(NIM, "Nim required")
    def test_generated_and_installed_builds(self):
        # An isolated project proves that checkout/user discovery is irrelevant.
        project = self.root / "project"
        (project / "tests").mkdir(parents=True)
        (project / "src").mkdir()
        source = project / "tests/probe.nim"
        source.write_text(
            'import quark/build/configuration\n'
            'static:\n'
            '  doAssert quarkGlobalSetting("marker") == "selected"\n'
            '  doAssert getEnv("ROUNDTRIP") == "a,b # & it\'s  "\n'
            '  doAssert quarkCanonicalBackend("QuAnTuM_EXpressions") == "qex"\n')
        source.write_text(source.read_text() + 'quarkBackendFlags("qex")\n')
        source.write_text("import std/os\n" + source.read_text())
        (source.parent / "second.nim").write_text(source.read_text())
        cfg = BackendConfig("qex", str(self.root))
        cfg.nimFlags = ["-p:" + str(ROOT / "src"),
                        "--putenv:ROUNDTRIP=a,b # & it's  "]
        cfg.passC = ["-I" + str(self.root)]
        conf = self.root / "custom config.conf"
        configure.write_quark_conf(conf, [cfg], "qex", NIM, {"marker": "selected"})
        configure.write_make_files(project, self.root, NIM, "qex", conf)
        env = {**os.environ, "QUARK_CONFIG": str(self.root / "wrong.conf")}
        result = subprocess.run(["make", "-C", str(self.root), "probe", "second",
                                 "BACKEND=QuAnTuM_EXpressions"],
                                env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / "bin/probe").exists())
        self.assertTrue((self.root / "bin/second").exists())
        nims = self.root / "quark.nims"
        configure.write_quark_nims(nims, [cfg], "qex", conf)
        with patch("build.configure.Path.home", return_value=self.root / "user"):
            installed = configure.install_user_config(conf, nims)
        conf.unlink()
        (project / "tests/config.nims").write_text(
            "include " + configure.nim_string(str(installed)) + "\n")
        result = subprocess.run([NIM, "c", "--hints:off", "-d:backend=Quantum-Expressions",
                                 "--nimcache:" + str(self.root / "installed-cache"),
                                 "--out:" + str(self.root / "installed-probe"), str(source)],
                                env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(NIM, "Nim required")
    def test_explicit_missing_config_and_unsupported_adapter(self):
        for flags, expected in [
            (["-d:quarkConfig=" + str(self.root / "missing")], "configuration does not exist"),
            (["-d:backend=QUDA"], "no conforming Quark adapter")]:
            result = subprocess.run([NIM, "check", "--hints:off", "--path:" + str(ROOT / "src"),
                                     *flags, str(ROOT / "src/quark/backend/backend.nim")],
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
