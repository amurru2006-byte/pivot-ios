"""Catch mismatched release metadata before an expensive iPhone build."""
import re
import unittest
from pathlib import Path


def check_sources(project, package, workflow):
    versions = re.findall(r'^\s+MARKETING_VERSION:\s*"(\d+\.\d+\.\d+)"\s*$', project, re.M)
    builds = re.findall(r'^\s+CURRENT_PROJECT_VERSION:\s*"([1-9]\d*)"\s*$', project, re.M)
    if len(versions) != 1 or len(builds) != 1:
        raise ValueError('invalid_project_version')
    version, build = versions[0], builds[0]
    app_versions = re.findall(r"CFBundleShortVersionString'\]\s*==\s*'([^']+)'", package)
    app_builds = re.findall(r"CFBundleVersion'\]\s*==\s*'([^']+)'", package)
    if len(app_versions) != 2 or app_versions != [version, version] or app_builds != [build, build]:
        raise ValueError('package_version_mismatch')
    if f"version='{version}', build={build}" not in package:
        raise ValueError('manifest_version_mismatch')
    for source in [package, workflow]:
        archives = re.findall(r'Pivot-\d+\.\d+\.\d+\.ipa', source)
        manifests = re.findall(r'Pivot-\d+\.\d+\.\d+-manifest\.json', source)
        if not archives or not manifests or any(value != f'Pivot-{version}.ipa' for value in archives) or any(value != f'Pivot-{version}-manifest.json' for value in manifests):
            raise ValueError('artifact_version_mismatch')
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

    def test_project_only_bump_is_rejected(self):
        changed = re.sub(r'MARKETING_VERSION: "[^"]+"', 'MARKETING_VERSION: "99.1.1"', self.project)
        with self.assertRaises(ValueError):
            check_sources(changed, self.package, self.workflow)

    def test_app_widget_build_mismatch_is_rejected(self):
        changed = re.sub(r"CFBundleVersion'\] == '\d+'", "CFBundleVersion'] == '99999'", self.package, count=1)
        with self.assertRaises(ValueError):
            check_sources(self.project, changed, self.workflow)

    def test_wrong_uploaded_artifact_is_rejected(self):
        changed = re.sub(r'Pivot-\d+\.\d+\.\d+\.ipa', 'Pivot-99.1.1.ipa', self.workflow)
        with self.assertRaises(ValueError):
            check_sources(self.project, self.package, changed)


if __name__ == '__main__':
    unittest.main()
