import io
from pathlib import Path
import plistlib
import tarfile
import tempfile
import unittest

from compiled_iphone import inspect_archive, verify_archive, project_version


class CompiledIPhoneTests(unittest.TestCase):
    def test_candidate_packager_uses_the_same_validated_project_version_as_build_verifier(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / 'Scripts/package-v8-candidate.sh').read_text(encoding='utf-8')
        self.assertEqual(source.count("version, build = project_version(Path('project.yml').read_text())"), 2)
        self.assertIn("assert info['CFBundleShortVersionString'] == version", source)
        self.assertIn("assert info['CFBundleVersion'] == build", source)
        self.assertIn("assert widget['CFBundleShortVersionString'] == version and widget['CFBundleVersion'] == build", source)
        self.assertIn('"../Pivot-$PIVOT_VERSION.ipa"', source)
        self.assertIn("dict(version=version, build=int(build)", source)
        self.assertNotRegex(source, r"Pivot-\d+\.\d+\.\d+|version='\d+\.\d+\.\d+'")

    commit = 'a' * 40

    def temporary(self):
        # Keep synthetic files inside the explicitly writable checkout on Windows.
        return tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent)

    def archive(self, path, *, extra=None, widget_version='0.8.4', executable_mode=0o755):
        with tarfile.open(path, 'w:gz') as archive:
            for prefix, identifier, executable, version in [
                ('Pivot.app', 'app.pivot.personal', 'Pivot', '0.8.4'),
                ('Pivot.app/PlugIns/PivotWorkoutWidget.appex', 'app.pivot.personal.workout', 'PivotWorkoutWidget', widget_version),
            ]:
                info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=executable, CFBundleShortVersionString=version, CFBundleVersion='26')
                for name, content, mode in [('Info.plist', plistlib.dumps(info), 0o644), (executable, b'synthetic executable', executable_mode)]:
                    member = tarfile.TarInfo(prefix + '/' + name); member.size = len(content); member.mode = mode
                    archive.addfile(member, io.BytesIO(content))
            if extra is not None:
                archive.addfile(extra)

    def test_round_trip_retains_source_binding_and_is_not_a_candidate(self):
        with self.temporary() as folder:
            path = Path(folder) / 'app.tar.gz'; self.archive(path)
            manifest = inspect_archive(path, self.commit, '0.8.4', '26')
            self.assertFalse(manifest['installable'])
            verify_archive(path, manifest, self.commit, '0.8.4', '26')
            with self.assertRaises(ValueError):
                verify_archive(path, manifest, 'b' * 40, '0.8.4', '26')

    def test_altered_digest_or_manifest_fields_are_rejected(self):
        with self.temporary() as folder:
            path = Path(folder) / 'app.tar.gz'; self.archive(path)
            manifest = inspect_archive(path, self.commit, '0.8.4', '26')
            for field, value in [('archive_sha256', '0' * 64), ('executable_sha256', '0' * 64), ('installable', True)]:
                changed = dict(manifest); changed[field] = value
                with self.assertRaises(ValueError): verify_archive(path, changed, self.commit, '0.8.4', '26')

    def test_mismatched_widget_and_lost_executable_modes_are_rejected(self):
        with self.temporary() as folder:
            path = Path(folder) / 'app.tar.gz'
            for options in [dict(widget_version='0.8.3'), dict(executable_mode=0o644)]:
                self.archive(path, **options)
                with self.assertRaises(ValueError): inspect_archive(path, self.commit, '0.8.4', '26')

    def test_paths_links_and_special_files_cannot_escape_the_app(self):
        with self.temporary() as folder:
            path = Path(folder) / 'app.tar.gz'
            traversal = tarfile.TarInfo('Pivot.app/../../outside')
            link = tarfile.TarInfo('Pivot.app/escape'); link.type = tarfile.SYMTYPE; link.linkname = '../../outside'
            device = tarfile.TarInfo('Pivot.app/device'); device.type = tarfile.CHRTYPE
            for entry in [traversal, link, device]:
                self.archive(path, extra=entry)
                with self.assertRaises(ValueError): inspect_archive(path, self.commit, '0.8.4', '26')

    def test_project_version_is_unique_and_explicit(self):
        source = '  MARKETING_VERSION: "0.8.4"\n  CURRENT_PROJECT_VERSION: "26"\n'
        self.assertEqual(project_version(source), ('0.8.4', '26'))
        with self.assertRaises(ValueError): project_version(source + source)


if __name__ == '__main__':
    unittest.main()
