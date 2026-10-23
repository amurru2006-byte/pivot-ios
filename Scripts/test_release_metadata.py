"""Catch mismatched release metadata before an expensive iPhone build."""
import re
import unittest
from pathlib import Path
from compiled_iphone import project_version


def check_sources(project, package, workflow):
    version, build = project_version(project)
    assignment = "version, build = project_version(Path('project.yml').read_text())"
    required = [
        "assert info['CFBundleShortVersionString'] == version",
        "assert info['CFBundleVersion'] == build",
        "assert widget['CFBundleShortVersionString'] == version and widget['CFBundleVersion'] == build",
    ]
    if package.count(assignment) != 2 or any(part not in package for part in required):
        raise ValueError('package_version_mismatch')
    if "dict(version=version, build=int(build), candidate=True," not in package:
        raise ValueError('manifest_version_mismatch')
    shell_version = 'print(project_version(Path("project.yml").read_text())[0])'
    if shell_version not in package or '"../Pivot-$PIVOT_VERSION.ipa"' not in package \
            or "Path(f'build/Pivot-{version}.ipa')" not in package \
            or "Path(f'build/Pivot-{version}-manifest.json')" not in package:
        raise ValueError('artifact_version_mismatch')
    candidate = workflow.split('name: Pivot-V8-iPhone-candidate', 1)
    if len(candidate) != 2:
        raise ValueError('missing_candidate_upload')
    upload = candidate[1].split('retention-days:', 1)[0]
    archives = re.findall(r'build/Pivot-[^\s]+\.ipa', upload)
    manifests = re.findall(r'build/Pivot-[^\s]+-manifest\.json', upload)
    if archives != ['build/Pivot-*.*.*.ipa'] or manifests != ['build/Pivot-*.*.*-manifest.json']:
        raise ValueError('uploaded_artifact_mismatch')
    return version, int(build)


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[1]
        self.project = (root / 'project.yml').read_text(encoding='utf-8')
        self.package = (root / 'Scripts/package-v8-candidate.sh').read_text(encoding='utf-8')
        self.workflow = (root / '.github/workflows/v8-calendar.yml').read_text(encoding='utf-8')

    def test_current_sources_match(self):
        version, build = check_sources(self.project, self.package, self.workflow)
        self.assertRegex(version, r'^\d+\.\d+\.\d+$')
        self.assertGreater(build, 0)

    def test_single_source_version_bump_is_used_by_every_candidate_check(self):
        changed = re.sub(r'MARKETING_VERSION: "[^"]+"', 'MARKETING_VERSION: "99.1.1"', self.project)
        self.assertEqual(check_sources(changed, self.package, self.workflow)[0], '99.1.1')

    def test_app_widget_build_mismatch_is_rejected(self):
        changed = self.package.replace("CFBundleVersion'] == build", "CFBundleVersion'] == '99999'", 1)
        with self.assertRaises(ValueError):
            check_sources(self.project, changed, self.workflow)

    def test_wrong_uploaded_artifact_is_rejected(self):
        changed = self.workflow.replace('Pivot-*.*.*.ipa', 'Pivot-99.1.1.ipa')
        with self.assertRaises(ValueError):
            check_sources(self.project, self.package, changed)


if __name__ == '__main__':
    unittest.main()
