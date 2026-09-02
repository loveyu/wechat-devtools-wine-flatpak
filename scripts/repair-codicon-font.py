#!/usr/bin/env python3

"""Repair WeChat DevTools Wine compatibility issues in-place.

The Windows Electron build loads its workbench CSS from app.asar. Under Wine,
the CSS is available during the first render, but the font URL inside the same
archive can enter a permanent error state. This tool extracts the official
bundled codicon and vscode-iconfont-patch fonts into the isolated Wine prefix,
then rewrites only their sources in fixed-size CSS entries. No ASAR offsets or
entry sizes are changed.

The renderer login actions also await a main-process login RPC. The main process
updates the global store by synchronously dispatching back to that renderer,
which deadlocks under Wine. The fixed-size action patches detach the RPC and
keep the local Redux update synchronous; errors remain contained in the
background promise.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import tempfile


FONT_ENTRY = (
    "js/libs/vseditor/static/base/browser/ui/codicons/codicon/codicon.ttf"
)
CSS_ENTRY = "js/libs/vseditor/static/workbench/workbench.desktop.main.css"
APP_CSS_ENTRY = "static/app.css"
FONT_SOURCE = b'local("codicon")'
PATCH_FONT_SOURCE = b'local("Develope-Tool-Icon")'
FONT_SOURCE_PATTERN = re.compile(
    rb'(?:url\([^)]*codicon[.]ttf[^)]*\)|local\(["\']?codicon["\']?\))'
    rb'(?:\s*format\([^)]*\))?',
    re.IGNORECASE,
)
PATCH_FONT_FACE_PATTERN = re.compile(
    rb"(@font-face\{font-family:vscode-iconfont-patch;src:)"
    rb"(.*?)"
    rb"(;font-weight:400;font-style:normal\})",
    re.DOTALL,
)
PATCH_FONT_DATA_PATTERN = re.compile(
    rb"^url\(data:font/truetype;charset=utf-8;base64,([A-Za-z0-9+/=]+)\)"
    rb'\s*format\("truetype"\)$'
)
LOGIN_ACTION_PATCHES = {
    "js/7e95e7a8ad7d87380f52a7f2cd91a9a6.js": (
        (
            b"constructor(e,r){super(),this.requestService=e,this.logService=r,"
            b"this._onStatusChange",
            b"constructor(e,r,i){super(),this.requestService=e,this.logService=r,"
            b"this.loginService=i,this._onStatusChange",
        ),
        (
            b"e.__decorate([e.__param(0,o.IRawRequestService),"
            b"e.__param(1,o.ILogService)],h)",
            b"e.__decorate([e.__param(0,o.IRawRequestService),"
            b"e.__param(1,o.ILogService),e.__param(2,o.ILoginService)],h)",
        ),
        (
            b'this.logService.info("[LoginState] qrcode-login-complete",'
            b"{from:u(r),codeTail:i,hasUser:Boolean(E.openid),"
            b"hasTicket:Boolean(E.newticket),hasSignature:Boolean(E.signature),"
            b"ticketExpiredSec:d.ticket_expired_time,"
            b"signatureExpiredSec:d.signature_expired_time,"
            b"ticketExpiredTime:E.ticketExpiredTime,"
            b"signatureExpiredTime:E.signatureExpiredTime}),"
            b"this._onStatusChange.fire({from:r,status:a.SUCCESS,errMsg:\"\","
            b"userInfo:E,end:!0})",
            b'this.logService.info("[LoginState] qrcode-login-complete",'
            b"{from:u(r),codeTail:i,hasUser:!!E.openid}),"
            b"r<2?setTimeout(()=>this.loginService.login(E,{}).then(()=>"
            b"this._onStatusChange.fire({from:r,status:a.SUCCESS,errMsg:\"\","
            b"userInfo:E,end:!0})).catch(e=>this.logService.error(e)),"
            b"250       ):this._onStatusChange.fire({from:r,status:a.SUCCESS,"
            b"errMsg:\"\",userInfo:E,end:!0})",
        ),
    ),
    "js/8dc0274d2658e9d1e37c20b034fb4416.js": (
        (b"return async(n,r,o)=>{", b"return n=>{"),
        (b"await c.login(u)", b"c.login(u,{}).catch(()=>{})"),
    ),
    "js/2714be6cfa3eef7ae9c1934282860836.js": (
        (
            b"loginSuccess:function(e){return async(i,n)=>{",
            b"loginSuccess:function(e){return (i,n) =>{",
        ),
        (b"await c.login(g)", b"c.login(g,{}).catch(()=>{})"),
        (b"hasUser:Boolean(e.openid)", b"hasUser:!!e.openid"),
    ),
}
class RepairError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_asar_header(archive: Path) -> tuple[dict, int]:
    with archive.open("rb") as stream:
        prefix = stream.read(16)
        if len(prefix) != 16:
            raise RepairError("app.asar 头部不完整")
        pickle_size, header_size, _string_size, json_size = struct.unpack(
            "<4I", prefix
        )
        if pickle_size != 4 or json_size == 0 or json_size > 64 * 1024 * 1024:
            raise RepairError("app.asar 头部格式不受支持")
        header_blob = stream.read(json_size)

    try:
        header = json.loads(header_blob.rstrip(b"\0").decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RepairError(f"无法解析 app.asar 目录：{error}") from error
    return header, 8 + header_size


def find_entry(header: dict, internal_path: str) -> dict:
    node = header
    for component in internal_path.split("/"):
        try:
            node = node["files"][component]
        except (KeyError, TypeError) as error:
            raise RepairError(f"app.asar 中缺少文件：{internal_path}") from error
    if "offset" not in node or "size" not in node:
        raise RepairError(f"app.asar 条目不是普通文件：{internal_path}")
    return node


def entry_location(header: dict, data_offset: int, internal_path: str) -> tuple[int, int]:
    entry = find_entry(header, internal_path)
    try:
        offset = data_offset + int(entry["offset"])
        size = int(entry["size"])
    except (TypeError, ValueError) as error:
        raise RepairError(f"app.asar 条目偏移无效：{internal_path}") from error
    if offset < data_offset or size < 1:
        raise RepairError(f"app.asar 条目范围无效：{internal_path}")
    return offset, size


def read_entry(archive: Path, offset: int, size: int) -> bytes:
    with archive.open("rb") as stream:
        stream.seek(offset)
        data = stream.read(size)
    if len(data) != size:
        raise RepairError("app.asar 文件条目不完整")
    return data


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def extract_font(archive: Path, header: dict, data_offset: int, output: Path) -> str:
    offset, size = entry_location(header, data_offset, FONT_ENTRY)
    if size > 2 * 1024 * 1024:
        raise RepairError("内置 codicon 字体大小异常")
    font = read_entry(archive, offset, size)
    if not (font.startswith(b"\x00\x01\x00\x00") or font.startswith(b"OTTO")):
        raise RepairError("内置 codicon 字体格式异常")
    digest = sha256(font)
    if not output.is_file() or sha256(output.read_bytes()) != digest:
        write_atomic(output, font)
    return digest


def decode_patch_font(source: bytes) -> bytes | None:
    match = PATCH_FONT_DATA_PATTERN.fullmatch(source)
    if not match:
        return None
    try:
        font = base64.b64decode(match.group(1), validate=True)
    except binascii.Error as error:
        raise RepairError("vscode-iconfont-patch Base64 数据无效") from error
    if len(font) > 2 * 1024 * 1024 or not (
        font.startswith(b"\x00\x01\x00\x00") or font.startswith(b"OTTO")
    ):
        raise RepairError("vscode-iconfont-patch 字体格式异常")
    return font


def load_patch_font_from_backups(backup_dir: Path) -> bytes | None:
    backups = sorted(
        backup_dir.glob("app-css-*.bin"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for backup in backups:
        match = PATCH_FONT_FACE_PATTERN.search(backup.read_bytes())
        if not match:
            continue
        font = decode_patch_font(match.group(2))
        if font is not None:
            return font
    return None


def patch_vscode_icon_font(
    archive: Path,
    header: dict,
    data_offset: int,
    backup_dir: Path,
    output: Path,
) -> tuple[str, str]:
    offset, size = entry_location(header, data_offset, APP_CSS_ENTRY)
    css = read_entry(archive, offset, size)
    matches = list(PATCH_FONT_FACE_PATTERN.finditer(css))
    if len(matches) != 1:
        raise RepairError(f"vscode-iconfont-patch 字体源数量异常：{len(matches)}")

    match = matches[0]
    current = match.group(2)
    font = decode_patch_font(current)
    patch_result = "unchanged" if current.rstrip() == PATCH_FONT_SOURCE else "patched"
    if font is None:
        font = load_patch_font_from_backups(backup_dir)
    if font is None and output.is_file():
        font = output.read_bytes()
    if font is None:
        raise RepairError("无法从应用 CSS 或备份恢复 vscode-iconfont-patch 字体")
    if len(font) > 2 * 1024 * 1024 or not (
        font.startswith(b"\x00\x01\x00\x00") or font.startswith(b"OTTO")
    ):
        raise RepairError("vscode-iconfont-patch 字体格式异常")

    font_digest = sha256(font)
    if not output.is_file() or sha256(output.read_bytes()) != font_digest:
        write_atomic(output, font)
    if patch_result == "unchanged":
        return patch_result, font_digest
    if len(PATCH_FONT_SOURCE) > len(current):
        raise RepairError("vscode-iconfont-patch 修复源超过原 ASAR 条目长度")

    replacement = PATCH_FONT_SOURCE + b" " * (len(current) - len(PATCH_FONT_SOURCE))
    repaired = css[: match.start(2)] + replacement + css[match.end(2) :]
    if len(repaired) != len(css):
        raise RepairError("vscode-iconfont-patch 修复会改变 ASAR 条目长度")

    original_digest = sha256(css)
    backup = backup_dir / f"app-css-{original_digest}.bin"
    if not backup.exists():
        write_atomic(backup, css)
    with archive.open("r+b") as stream:
        stream.seek(offset)
        stream.write(repaired)
        stream.flush()
        os.fsync(stream.fileno())
    return patch_result, font_digest


def patch_css(archive: Path, header: dict, data_offset: int, backup_dir: Path) -> str:
    offset, size = entry_location(header, data_offset, CSS_ENTRY)
    css = read_entry(archive, offset, size)
    matches = list(FONT_SOURCE_PATTERN.finditer(css))
    if len(matches) != 1:
        raise RepairError(f"codicon 字体 URL 数量异常：{len(matches)}")

    match = matches[0]
    current = match.group(0)
    if current.rstrip() == FONT_SOURCE:
        return "unchanged"
    if len(FONT_SOURCE) > len(current):
        raise RepairError("codicon 修复源超过原 ASAR 条目长度")

    replacement = FONT_SOURCE + b" " * (len(current) - len(FONT_SOURCE))
    repaired = css[: match.start()] + replacement + css[match.end() :]
    if len(repaired) != len(css):
        raise RepairError("修复会改变 ASAR 条目长度")

    original_digest = sha256(css)
    backup = backup_dir / f"workbench-css-{original_digest}.bin"
    if not backup.exists():
        write_atomic(backup, css)

    with archive.open("r+b") as stream:
        stream.seek(offset)
        stream.write(repaired)
        stream.flush()
        os.fsync(stream.fileno())
    return "patched"


def patch_login_actions(
    archive: Path,
    header: dict,
    data_offset: int,
    backup_dir: Path,
) -> str:
    results = []
    for internal_path, replacements in LOGIN_ACTION_PATCHES.items():
        offset, size = entry_location(header, data_offset, internal_path)
        source = read_entry(archive, offset, size)
        original_source = source
        old_counts = [source.count(old) for old, _new in replacements]
        new_counts = [source.count(new) for _old, new in replacements]

        if all(count == 0 for count in old_counts) and all(
            count == 1 for count in new_counts
        ):
            repaired = source
        elif all(count == 1 for count in old_counts) and all(
            count == 0 for count in new_counts
        ):
            repaired = source
            for old, new in replacements:
                repaired = repaired.replace(old, new, 1)
        else:
            raise RepairError(
                f"登录 IPC 修复目标不匹配：{internal_path} "
                f"old={old_counts},new={new_counts}"
            )

        if len(repaired) != len(original_source):
            raise RepairError(f"登录 IPC 修复会改变 ASAR 条目长度：{internal_path}")
        if repaired == original_source:
            results.append("unchanged")
            continue

        original_digest = sha256(original_source)
        backup = backup_dir / f"{Path(internal_path).stem}-{original_digest}.bin"
        if not backup.exists():
            write_atomic(backup, original_source)
        with archive.open("r+b") as stream:
            stream.seek(offset)
            stream.write(repaired)
            stream.flush()
            os.fsync(stream.fileno())
        results.append("patched")

    return "patched" if "patched" in results else "unchanged"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--wine-prefix", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    archive = arguments.archive.resolve()
    if not archive.is_file():
        raise RepairError(f"找不到 app.asar：{archive}")

    header, data_offset = read_asar_header(archive)
    font_output = arguments.wine_prefix / "drive_c/windows/Fonts/codicon.ttf"
    font_digest = extract_font(archive, header, data_offset, font_output)
    patch_font_output = (
        arguments.wine_prefix
        / "drive_c/windows/Fonts/vscode-iconfont-patch.ttf"
    )
    patch_font_result, patch_font_digest = patch_vscode_icon_font(
        archive,
        header,
        data_offset,
        arguments.state_dir / "repairs/codicon",
        patch_font_output,
    )
    patch_result = patch_css(
        archive,
        header,
        data_offset,
        arguments.state_dir / "repairs/codicon",
    )
    login_result = patch_login_actions(
        archive,
        header,
        data_offset,
        arguments.state_dir / "repairs/login-ipc",
    )
    print(
        f"codicon={patch_result},font_sha256={font_digest},font={font_output},"
        f"vscode_patch={patch_font_result},"
        f"patch_font_sha256={patch_font_digest},patch_font={patch_font_output},"
        f"login_ipc={login_result}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RepairError as error:
        print(f"codicon 修复失败：{error}", file=sys.stderr)
        sys.exit(1)
