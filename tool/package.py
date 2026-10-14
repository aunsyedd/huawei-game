"""Creates upload-ready zips in dist/ (each well under 100 MB).

    flutter build web --release      # first, for the playable zip
    python tool/package.py

dist/HazeRoyale-source.zip  everything needed to rebuild (no build caches)
dist/HazeRoyale-web.zip     the playable web build (upload to any static host)
"""
import os
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DIST = os.path.join(ROOT, 'dist')

# Generated or machine-specific; Flutter recreates these with `flutter pub get`.
SKIP_DIRS = {'build', '.dart_tool', '.git', '.idea', '.vercel', '.claude', 'dist', 'flutter-sdk', '.gradle'}
SKIP_FILES = {'.env.local', '.flutter-plugins-dependencies', 'local.properties'}
SKIP_EXT = {'.iml', '.log'}


def zip_dir(src, dest, skip=True):
    count = 0
    with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for folder, dirs, files in os.walk(src):
            if skip:
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for f in files:
                if skip and (f in SKIP_FILES or os.path.splitext(f)[1] in SKIP_EXT):
                    continue
                path = os.path.join(folder, f)
                z.write(path, os.path.relpath(path, src))
                count += 1
    return count


def mb(path):
    return os.path.getsize(path) / 1024 / 1024


if __name__ == '__main__':
    os.makedirs(DIST, exist_ok=True)
    src_zip = os.path.join(DIST, 'HazeRoyale-source.zip')
    n = zip_dir(ROOT, src_zip)
    print(f'{os.path.basename(src_zip):28s} {mb(src_zip):6.1f} MB  ({n} files)')

    web = os.path.join(ROOT, 'build', 'web')
    if os.path.isdir(web):
        web_zip = os.path.join(DIST, 'HazeRoyale-web.zip')
        n = zip_dir(web, web_zip, skip=False)
        print(f'{os.path.basename(web_zip):28s} {mb(web_zip):6.1f} MB  ({n} files)')
    else:
        print('build/web missing: run `flutter build web --release` for the playable zip')

    for name in os.listdir(DIST):
        assert mb(os.path.join(DIST, name)) < 100, f'{name} is over 100 MB'
