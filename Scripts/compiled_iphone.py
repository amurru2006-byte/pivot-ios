"""Bind an unsigned, mode-preserving iPhone build to its exact source commit.

This intermediate archive is not an installable candidate. The release job
must independently verify every UI shard before signing and packaging it.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import re
import tarfile


def require(condition, code):
    if not condition:
        raise ValueError(code)


def project_version(source):
    versions = re.findall(r'^\s+MARKETING_VERSION:\s*"(\d+\.\d+\.\d+)"\s*$', source, re.M)
    builds = re.findall(r'^\s+CURRENT_PROJECT_VERSION:\s*"([1-9]\d*)"\s*$', source, re.M)
    require(len(versions) == len(builds) == 1, 'project_metadata')
    return versions[0], builds[0]


def inspect_archive(path, commit, version, build):
    require(re.fullmatch(r'[0-9a-f]{40}', commit) is not None, 'commit')
    require(0 < path.stat().st_size <= 256 * 1024 * 1024, 'archive_size')
    with tarfile.open(path, 'r:gz') as archive:
        members = archive.getmembers()
        require(0 < len(members) <= 10000, 'entry_count')
        require(sum(member.size for member in members) <= 512 * 1024 * 1024, 'expansion')
        names = [member.name.rstrip('/') for member in members]
        require(len(set(names)) == len(names), 'duplicate_path')
        for member in members:
            name = PurePosixPath(member.name)
            require(not name.is_absolute() and '..' not in name.parts and '\\' not in member.name
                    and name.parts and name.parts[0] == 'Pivot.app', 'entry_path')
            require(member.isfile() or member.isdir() or member.issym() or member.islnk(), 'entry_type')
            if member.issym() or member.islnk():
                target = member.linkname
                require(not target.startswith('/') and '\\' not in target, 'link_path')
                resolved = posixpath.normpath(posixpath.join(str(name.parent), target) if member.issym() else target)
                require(resolved == 'Pivot.app' or resolved.startswith('Pivot.app/'), 'link_escape')

        def read_regular(name):
            member = archive.getmember(name)
            require(member.isfile(), 'metadata_type')
            return archive.extractfile(member).read()

        app = plistlib.loads(read_regular('Pivot.app/Info.plist'))
        widget = plistlib.loads(read_regular('Pivot.app/PlugIns/PivotWorkoutWidget.appex/Info.plist'))
        require(app.get('CFBundleIdentifier') == 'app.pivot.personal', 'app_identity')
        require(widget.get('CFBundleIdentifier') == 'app.pivot.personal.workout', 'widget_identity')
        for info in (app, widget):
            require(info.get('CFBundleShortVersionString') == version and info.get('CFBundleVersion') == str(build), 'version')
            require(re.fullmatch(r'[A-Za-z0-9_-]+', info.get('CFBundleExecutable', '')) is not None, 'executable')
        executable = 'Pivot.app/' + app['CFBundleExecutable']
        widget_executable = 'Pivot.app/PlugIns/PivotWorkoutWidget.appex/' + widget['CFBundleExecutable']
        for name in (executable, widget_executable):
            require(archive.getmember(name).mode & 0o111, 'executable_mode')
            require(len(read_regular(name)) > 0, 'empty_executable')
        executable_hash = hashlib.sha256(read_regular(executable)).hexdigest()
    return dict(commit=commit, version=version, build=str(build),
                archive_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                executable_sha256=executable_hash, installable=False)


def verify_archive(path, manifest, commit, version, build):
    require(isinstance(manifest, dict) and manifest.get('commit') == commit
            and manifest.get('version') == version and manifest.get('build') == str(build)
            and manifest.get('installable') is False, 'build_identity')
    require(0 < path.stat().st_size <= 256 * 1024 * 1024, 'archive_size')
    require(manifest.get('archive_sha256') == hashlib.sha256(path.read_bytes()).hexdigest(), 'archive_digest')
    require(manifest == inspect_archive(path, commit, version, build), 'build_manifest_mismatch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['create', 'verify'])
    parser.add_argument('archive', type=Path)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    version, build = project_version((Path(__file__).resolve().parents[1] / 'project.yml').read_text(encoding='utf-8'))
    if args.mode == 'create':
        value = inspect_archive(args.archive, args.commit, version, build)
        args.manifest.write_text(json.dumps(value, sort_keys=True) + '\n', encoding='utf-8')
    else:
        verify_archive(args.archive, json.loads(args.manifest.read_text(encoding='utf-8')), args.commit, version, build)
    print('Intermediate iPhone build verified; not an installable candidate.')


if __name__ == '__main__':
    main()
