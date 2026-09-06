#!/bin/bash -p
case "$-" in *p*) ;; *) /usr/bin/printf '%s\n' 'Release shell entry requires Bash privileged mode.' >&2; exit 78 ;; esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
export LC_ALL=C
unset CDPATH
umask 022

# The build, package, and local verification paths never invoke GitHub, a GUI,
# Developer ID signing, notarization, or a fallback.  The explicit verify-public
# command performs only unauthenticated reads from fixed public GitHub URLs.
# Debug builds and test fixtures are never accepted by these production paths.
product='LectureBoard AI'
bundle_id='io.github.akiyama709.LectureBoardAI'
version='1.0.0'
tag='v1.0.0'
release_test_evidence_name='LectureBoard-AI-v1.0.0-test-results.json'
release_payload_name_list=$'LectureBoard-AI-v1.0.0-arm64.zip\nLectureBoard-AI-v1.0.0-test-results.json\nSBOM.spdx.json\nprovenance.json'
release_asset_name_list=$'LectureBoard-AI-v1.0.0-arm64.zip\nLectureBoard-AI-v1.0.0-test-results.json\nSBOM.spdx.json\nSHA256SUMS\nprovenance.json'
die() { /usr/bin/printf 'no-fee v1 release failed: %s\n' "$1" >&2; exit 1; }
usage() {
  /usr/bin/printf '%s\n' \
    "Usage: $(/usr/bin/basename -- "$0") evidence --source-dir DIR --commit OID --output-dir DIR" \
    "       $(/usr/bin/basename -- "$0") prepare --source-dir DIR --tag v1.0.0 --commit OID --test-result FILE --test-result-bundle DIR --gate-log FILE --output-dir DIR" \
    "       $(/usr/bin/basename -- "$0") verify --archive ZIP --checksum FILE --sbom FILE --provenance FILE --test-result FILE --commit OID" \
    "       $(/usr/bin/basename -- "$0") compare-public --approved-dir DIR --downloaded-dir DIR --release-metadata FILE --tag-refs FILE --commit OID" \
    "       $(/usr/bin/basename -- "$0") verify-public --source-dir DIR --approved-dir DIR --commit OID --output-dir DIR"
}
abs_dir() { [[ "$1" == /* && "$1" != '/' ]] || die "$2 must be an absolute non-root path"; }
regular() { [[ "$1" == /* && -f "$1" && ! -L "$1" ]] || die "$2 must be an absolute regular file"; }
oid() {
  [[ "$1" =~ ^[0-9a-fA-F]{40}$ || "$1" =~ ^[0-9a-fA-F]{64}$ ]] \
    || die "$2 must be a full commit object identifier"
  [[ "$1" != 0000000000000000000000000000000000000000 \
    && "$1" != 0000000000000000000000000000000000000000000000000000000000000000 ]] \
    || die "$2 must not be Git's null object identifier"
}
json_string() { [[ "$1" != *'"'* && "$1" != *$'\n'* && "$1" != *'\\'* ]] || die 'unsafe metadata value'; }
sha256() { /usr/bin/python3 -I -c 'import hashlib,sys
h=hashlib.sha256()
with open(sys.argv[1],"rb") as stream:
 while True:
  chunk=stream.read(1024*1024)
  if not chunk: break
  h.update(chunk)
print(h.hexdigest())' "$1"; }
lower() { /usr/bin/tr '[:upper:]' '[:lower:]' <<<"$1"; }
bounded_regular() {
  local path="$1" label="$2" maximum="$3" size
  regular "$path" "$label"
  size="$(/usr/bin/stat -f '%z' "$path")" || die "$label size could not be read"
  [[ "$size" =~ ^[0-9]+$ ]] || die "$label size is malformed"
  (( size <= maximum )) || die "$label exceeds its size limit"
}
directory_identity() {
  local path="$1" identity
  [[ "$path" == /* && "$path" != / && -d "$path" && ! -L "$path" ]] || return 1
  identity="$(/usr/bin/stat -f '%d %i' "$path")" || return 1
  [[ "$identity" =~ ^[0-9]+\ [0-9]+$ ]] || return 1
  /usr/bin/printf '%s\n' "$identity"
}
regular_file_matches_sha256() {
  local path="$1" expected_digest="$2"
  [[ "$path" == /* && "$path" != / && "$expected_digest" =~ ^[0-9a-f]{64}$ ]] \
    || return 1
  /usr/bin/python3 -I - "$path" "$expected_digest" <<'PY'
import hashlib,os,stat,sys
path,expected=sys.argv[1:]
def identity(value):
 return (value.st_dev,value.st_ino,value.st_mode,value.st_uid,value.st_gid,value.st_size,
         value.st_mtime_ns,value.st_ctime_ns,getattr(value,"st_flags",0))
try:
 path_before=os.lstat(path)
 if not stat.S_ISREG(path_before.st_mode) or stat.S_ISLNK(path_before.st_mode):
  raise ValueError("not a regular file")
 descriptor=os.open(path,os.O_RDONLY|os.O_CLOEXEC|os.O_NOFOLLOW)
 try:
  descriptor_before=os.fstat(descriptor)
  if identity(descriptor_before)!=identity(path_before):
   raise ValueError("file identity changed before hashing")
  digest=hashlib.sha256()
  while True:
   chunk=os.read(descriptor,1024*1024)
   if not chunk: break
   digest.update(chunk)
  descriptor_after=os.fstat(descriptor)
 finally:
  os.close(descriptor)
 path_after=os.lstat(path)
except (OSError,ValueError):
 raise SystemExit(1)
if (identity(descriptor_before)!=identity(descriptor_after)
    or identity(path_before)!=identity(path_after)
    or digest.hexdigest()!=expected):
 raise SystemExit(1)
PY
}
private_evidence_directory_is_exact() {
  local directory="$1" result_bundle_name="$2"
  [[ "$directory" == /* && "$directory" != / ]] || return 1
  /usr/bin/python3 -I - "$directory" "$result_bundle_name" \
    "$release_test_evidence_name" <<'PY'
import os,re,stat,sys
directory,result_name,evidence_name=sys.argv[1:]
if (not re.fullmatch(r"Test-LectureBoardAI-[0-9._+-]+\.xcresult",result_name)
    or os.path.basename(result_name)!=result_name):
 raise SystemExit(1)
try:
 root=os.lstat(directory)
 if not stat.S_ISDIR(root.st_mode) or stat.S_ISLNK(root.st_mode): raise ValueError()
 entries=os.listdir(directory)
 expected={evidence_name,"prepublication-gate.log",result_name}
 if len(entries)!=3 or set(entries)!=expected: raise ValueError()
 for name in entries:
  value=os.lstat(os.path.join(directory,name))
  if stat.S_ISLNK(value.st_mode): raise ValueError()
  if name==result_name:
   if not stat.S_ISDIR(value.st_mode): raise ValueError()
  elif not stat.S_ISREG(value.st_mode):
   raise ValueError()
except (OSError,ValueError):
 raise SystemExit(1)
PY
}
delete_directory_with_identity() {
  local parent="$1" expected_parent_identity="$2" target="$3" expected_target_identity="$4"
  local parent_device parent_inode target_device target_inode
  [[ "$parent" == /* && "$parent" != / && "$target" == /* && "$target" != / \
    && "$(/usr/bin/dirname -- "$target")" == "$parent" \
    && "$expected_parent_identity" =~ ^[0-9]+\ [0-9]+$ \
    && "$expected_target_identity" =~ ^[0-9]+\ [0-9]+$ ]] || return 1
  parent_device="${expected_parent_identity% *}"
  parent_inode="${expected_parent_identity#* }"
  target_device="${expected_target_identity% *}"
  target_inode="${expected_target_identity#* }"
  /usr/bin/python3 -I - "$parent" "${target##*/}" \
    "$parent_device" "$parent_inode" "$target_device" "$target_inode" <<'PY'
import os,stat,sys
parent,name,pdev,pino,tdev,tino=sys.argv[1:]
expected_parent=(int(pdev),int(pino)); expected_target=(int(tdev),int(tino))
if not name or name in {".",".."} or "/" in name: raise SystemExit(1)
flags=os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC|os.O_NOFOLLOW
def object_id(value): return (value.st_dev,value.st_ino)
def open_directory(name,dir_fd=None):
 descriptor=os.open(name,flags,dir_fd=dir_fd)
 value=os.fstat(descriptor)
 if not stat.S_ISDIR(value.st_mode):
  os.close(descriptor); raise OSError("not a directory")
 return descriptor,value
def clear_directory(descriptor):
 for child in sorted(os.listdir(descriptor)):
  before=os.stat(child,dir_fd=descriptor,follow_symlinks=False)
  if stat.S_ISDIR(before.st_mode) and not stat.S_ISLNK(before.st_mode):
   child_fd,opened=open_directory(child,descriptor)
   try:
    if object_id(opened)!=object_id(before): raise OSError("child identity changed")
    clear_directory(child_fd)
    after_fd=os.fstat(child_fd)
    after_name=os.stat(child,dir_fd=descriptor,follow_symlinks=False)
    if (object_id(after_fd)!=object_id(opened)
        or object_id(after_name)!=object_id(opened)): raise OSError("child replaced")
   finally:
    os.close(child_fd)
   os.rmdir(child,dir_fd=descriptor)
  else:
   os.unlink(child,dir_fd=descriptor)
try:
 parent_fd,parent_status=open_directory(parent)
 try:
  if object_id(parent_status)!=expected_parent: raise OSError("parent replaced")
  named_status=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)
  if not stat.S_ISDIR(named_status.st_mode) or object_id(named_status)!=expected_target:
   raise OSError("target replaced")
  target_fd,target_status=open_directory(name,parent_fd)
  try:
   if object_id(target_status)!=expected_target: raise OSError("target changed before open")
   clear_directory(target_fd)
   final_fd=os.fstat(target_fd)
   final_name=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)
   if object_id(final_fd)!=expected_target or object_id(final_name)!=expected_target:
    raise OSError("target replaced before removal")
  finally:
   os.close(target_fd)
  os.rmdir(name,dir_fd=parent_fd)
 finally:
  os.close(parent_fd)
except OSError:
 raise SystemExit(1)
PY
}
directory_descriptor_matches_identity() {
  local descriptor="$1" expected_identity="$2" expected_device expected_inode
  [[ "$descriptor" =~ ^[3-9][0-9]*$ \
    && "$expected_identity" =~ ^[0-9]+\ [0-9]+$ ]] || return 1
  expected_device="${expected_identity% *}"
  expected_inode="${expected_identity#* }"
  /usr/bin/python3 -I - "$descriptor" "$expected_device" "$expected_inode" <<'PY'
import os,stat,sys
try:
 value=os.fstat(int(sys.argv[1]))
except (OSError,ValueError):
 raise SystemExit(1)
if not stat.S_ISDIR(value.st_mode) or (value.st_dev,value.st_ino)!=(int(sys.argv[2]),int(sys.argv[3])):
 raise SystemExit(1)
PY
}
delete_directory_from_descriptors_with_identity() {
  local parent_descriptor="$1" target_descriptor="$2"
  local expected_parent_identity="$3" expected_target_identity="$4"
  local parent_device parent_inode target_device target_inode
  [[ "$parent_descriptor" =~ ^[3-9][0-9]*$ \
    && "$target_descriptor" =~ ^[3-9][0-9]*$ \
    && "$expected_parent_identity" =~ ^[0-9]+\ [0-9]+$ \
    && "$expected_target_identity" =~ ^[0-9]+\ [0-9]+$ ]] || return 1
  parent_device="${expected_parent_identity% *}"
  parent_inode="${expected_parent_identity#* }"
  target_device="${expected_target_identity% *}"
  target_inode="${expected_target_identity#* }"
  /usr/bin/python3 -I - "$parent_descriptor" "$target_descriptor" \
    "$parent_device" "$parent_inode" "$target_device" "$target_inode" <<'PY'
import os,stat,sys
parent_fd,target_fd,pdev,pino,tdev,tino=map(int,sys.argv[1:])
expected_parent=(pdev,pino); expected_target=(tdev,tino)
flags=os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC|os.O_NOFOLLOW
def object_id(value): return (value.st_dev,value.st_ino)
def open_directory(name,dir_fd):
 descriptor=os.open(name,flags,dir_fd=dir_fd)
 value=os.fstat(descriptor)
 if not stat.S_ISDIR(value.st_mode):
  os.close(descriptor); raise OSError("not a directory")
 return descriptor,value
def clear_directory(descriptor):
 for child in sorted(os.listdir(descriptor)):
  before=os.stat(child,dir_fd=descriptor,follow_symlinks=False)
  if stat.S_ISDIR(before.st_mode) and not stat.S_ISLNK(before.st_mode):
   child_fd,opened=open_directory(child,descriptor)
   try:
    if object_id(opened)!=object_id(before): raise OSError("child identity changed")
    clear_directory(child_fd)
    after_fd=os.fstat(child_fd)
    after_name=os.stat(child,dir_fd=descriptor,follow_symlinks=False)
    if object_id(after_fd)!=object_id(opened) or object_id(after_name)!=object_id(opened):
     raise OSError("child replaced")
   finally:
    os.close(child_fd)
   os.rmdir(child,dir_fd=descriptor)
  else:
   os.unlink(child,dir_fd=descriptor)
try:
 parent_status=os.fstat(parent_fd); target_status=os.fstat(target_fd)
 if (not stat.S_ISDIR(parent_status.st_mode) or object_id(parent_status)!=expected_parent
     or not stat.S_ISDIR(target_status.st_mode) or object_id(target_status)!=expected_target):
  raise OSError("retained descriptor identity changed")
 matches=[]
 for name in os.listdir(parent_fd):
  value=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)
  if stat.S_ISDIR(value.st_mode) and object_id(value)==expected_target: matches.append(name)
 if not matches:
  raise OSError("retained directory is not a direct child of its retained parent")
 if len(matches)!=1: raise OSError("ambiguous retained directory")
 name=matches[0]
 opened_fd,opened_status=open_directory(name,parent_fd)
 try:
  if object_id(opened_status)!=expected_target: raise OSError("retained directory replaced")
  clear_directory(opened_fd)
  final_fd=os.fstat(opened_fd)
  final_name=os.stat(name,dir_fd=parent_fd,follow_symlinks=False)
  if object_id(final_fd)!=expected_target or object_id(final_name)!=expected_target:
   raise OSError("retained directory replaced before removal")
 finally:
  os.close(opened_fd)
 os.rmdir(name,dir_fd=parent_fd)
except OSError:
 raise SystemExit(1)
PY
}
cleanup_known_evidence_handoff() {
  local parent="$1" expected_parent_identity="$2" stage="$3" output="$4"
  local expected_stage_identity="$5" parent_descriptor="${6:-}" stage_descriptor="${7:-}"
  local candidate candidate_identity
  [[ "$parent" == /* && "$parent" != / \
    && "$expected_parent_identity" =~ ^[0-9]+\ [0-9]+$ \
    && "$expected_stage_identity" =~ ^[0-9]+\ [0-9]+$ \
    && "$stage" == /* && "$output" == /* && "$stage" != "$output" \
    && "$(/usr/bin/dirname -- "$stage")" == "$parent" \
    && "$(/usr/bin/dirname -- "$output")" == "$parent" \
    && "${stage##*/}" == .lectureboard-v1-evidence.* ]] \
    || return 1
  if [[ -n "$parent_descriptor" || -n "$stage_descriptor" ]]; then
    [[ -n "$parent_descriptor" && -n "$stage_descriptor" ]] || return 1
    delete_directory_from_descriptors_with_identity \
      "$parent_descriptor" "$stage_descriptor" \
      "$expected_parent_identity" "$expected_stage_identity"
    return
  fi
  [[ -d "$parent" && ! -L "$parent" \
    && "$(directory_identity "$parent")" == "$expected_parent_identity" ]] || return 1
  for candidate in "$stage" "$output"; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    [[ -d "$candidate" && ! -L "$candidate" ]] || continue
    candidate_identity="$(directory_identity "$candidate")" || continue
    [[ "$candidate_identity" == "$expected_stage_identity" ]] || continue
    delete_directory_with_identity "$parent" "$expected_parent_identity" \
      "$candidate" "$expected_stage_identity" || return 1
  done
}
evidence_handoff_identities_are_valid() {
  local parent="$1" expected_parent_identity="$2" stage="$3" output="$4"
  local expected_stage_identity="$5" parent_descriptor="$6" stage_descriptor="$7"
  local parent_device parent_inode stage_device stage_inode
  [[ "$parent" == /* && "$parent" != / && "$stage" == /* && "$output" == /* \
    && "$stage" != "$output" && "$(/usr/bin/dirname -- "$stage")" == "$parent" \
    && "$(/usr/bin/dirname -- "$output")" == "$parent" \
    && "$expected_parent_identity" =~ ^[0-9]+\ [0-9]+$ \
    && "$expected_stage_identity" =~ ^[0-9]+\ [0-9]+$ \
    && "$parent_descriptor" =~ ^[3-9][0-9]*$ \
    && "$stage_descriptor" =~ ^[3-9][0-9]*$ ]] || return 1
  parent_device="${expected_parent_identity% *}"; parent_inode="${expected_parent_identity#* }"
  stage_device="${expected_stage_identity% *}"; stage_inode="${expected_stage_identity#* }"
  /usr/bin/python3 -I - "$parent" "${stage##*/}" "${output##*/}" \
    "$parent_descriptor" "$stage_descriptor" "$parent_device" "$parent_inode" \
    "$stage_device" "$stage_inode" <<'PY'
import os,stat,sys
parent,stage_name,output_name,pfd,sfd,pdev,pino,sdev,sino=sys.argv[1:]
pfd,sfd,pdev,pino,sdev,sino=map(int,(pfd,sfd,pdev,pino,sdev,sino))
expected_parent=(pdev,pino); expected_stage=(sdev,sino)
def object_id(value): return (value.st_dev,value.st_ino)
try:
 parent_fd=os.fstat(pfd); stage_fd=os.fstat(sfd); parent_path=os.lstat(parent)
 output_path=os.lstat(os.path.join(parent,output_name))
 output_at_fd=os.stat(output_name,dir_fd=pfd,follow_symlinks=False)
 try:
  os.stat(stage_name,dir_fd=pfd,follow_symlinks=False)
 except FileNotFoundError:
  pass
 else:
  raise OSError("stage name still exists")
except OSError:
 raise SystemExit(1)
if (not stat.S_ISDIR(parent_fd.st_mode) or object_id(parent_fd)!=expected_parent
    or not stat.S_ISDIR(parent_path.st_mode) or object_id(parent_path)!=expected_parent
    or not stat.S_ISDIR(stage_fd.st_mode) or object_id(stage_fd)!=expected_stage
    or not stat.S_ISDIR(output_path.st_mode) or object_id(output_path)!=expected_stage
    or not stat.S_ISDIR(output_at_fd.st_mode) or object_id(output_at_fd)!=expected_stage):
 raise SystemExit(1)
PY
}
post_handoff_validation_pause() {
  :
}
post_handoff_final_token_pause() {
  :
}
published_evidence_content_is_valid() {
  local evidence_path="$1" result_bundle="$2" source_root="$3" expected_commit="$4"
  local gate_log="$5"
  release_test_evidence_is_valid "$evidence_path" "$expected_commit" \
    && release_test_evidence_tree_digest_matches \
      "$evidence_path" "$result_bundle" "$source_root" \
    && release_gate_log_matches "$evidence_path" "$gate_log" \
    && release_gate_script_matches_commit "$evidence_path" "$source_root" "$expected_commit"
}
validate_published_evidence_handoff() {
  local parent="$1" expected_parent_identity="$2" stage="$3" output="$4"
  local expected_stage_identity="$5" parent_descriptor="$6" stage_descriptor="$7"
  local result_bundle_name="$8" evidence_digest="$9" source_root="${10}" expected_commit="${11}"
  local evidence_path="$output/$release_test_evidence_name"
  local result_bundle="$output/$result_bundle_name" gate_log="$output/prepublication-gate.log"
  local token_before token_after token_final
  evidence_handoff_identities_are_valid "$parent" "$expected_parent_identity" \
    "$stage" "$output" "$expected_stage_identity" "$parent_descriptor" "$stage_descriptor" \
    || return 1
  private_evidence_directory_is_exact "$output" "$result_bundle_name" || return 1
  regular_file_matches_sha256 "$evidence_path" "$evidence_digest" || return 1
  token_before="$(result_bundle_stability_token "$output")" || return 1
  evidence_handoff_identities_are_valid "$parent" "$expected_parent_identity" \
    "$stage" "$output" "$expected_stage_identity" "$parent_descriptor" "$stage_descriptor" \
    || return 1
  published_evidence_content_is_valid \
    "$evidence_path" "$result_bundle" "$source_root" "$expected_commit" "$gate_log" \
    || return 1
  post_handoff_validation_pause || return 1
  token_after="$(result_bundle_stability_token "$output")" || return 1
  [[ "$token_after" == "$token_before" ]] || return 1
  evidence_handoff_identities_are_valid "$parent" "$expected_parent_identity" \
    "$stage" "$output" "$expected_stage_identity" "$parent_descriptor" "$stage_descriptor" \
    || return 1
  private_evidence_directory_is_exact "$output" "$result_bundle_name" || return 1
  regular_file_matches_sha256 "$evidence_path" "$evidence_digest" || return 1
  post_handoff_final_token_pause || return 1
  token_final="$(result_bundle_stability_token "$output")" || return 1
  [[ "$token_final" == "$token_before" ]]
}
hardened_runtime_flag_is_set() {
  local signature_details="$1" flags_hex flags_value
  flags_hex="$(
    /usr/bin/sed -nE \
      's/^CodeDirectory .* flags=0x([0-9A-Fa-f]+)(\([^)]*\))?.*$/\1/p' \
      <<<"$signature_details"
  )" || return 1
  [[ "$flags_hex" =~ ^[0-9A-Fa-f]+$ ]] || return 1
  flags_value=$((16#$flags_hex))
  (( (flags_value & 0x10000) == 0x10000 ))
}

create_portable_zip() {
  local source_app="$1" destination_archive="$2"
  # Emit one canonical, streaming ZIP with explicit Unix modes and no comments,
  # resource forks, ACLs, extended attributes, AppleDouble records, or extra fields.
  if ! /usr/bin/python3 -I - "$source_app" "$destination_archive" <<'PY'
import os,stat,sys,time,zipfile
root,out=sys.argv[1:]
if not os.path.isabs(root) or not os.path.isdir(root) or os.path.islink(root): raise SystemExit(1)
parent=os.path.dirname(root); total=0; entries=0
def walk_error(error):
 raise error
def stamp(value):
 result=time.localtime(value)[:6]
 return (1980,1,1,0,0,0) if result[0]<1980 else result
with zipfile.ZipFile(out,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9,allowZip64=False) as archive:
 archive.comment=b''
 for current,dirs,files in os.walk(root,topdown=True,onerror=walk_error,followlinks=False):
  dirs.sort(); files.sort()
  current_stat=os.lstat(current)
  if not stat.S_ISDIR(current_stat.st_mode) or current_stat.st_mode&0o500!=0o500: raise SystemExit(1)
  relative=os.path.relpath(current,parent).replace(os.sep,'/')+'/'
  info=zipfile.ZipInfo(relative,stamp(current_stat.st_mtime)); info.create_system=3
  info.external_attr=(stat.S_IFDIR|stat.S_IMODE(current_stat.st_mode))<<16
  info.compress_type=zipfile.ZIP_STORED; info.extra=b''; info.comment=b''
  archive.writestr(info,b''); entries+=1
  for name in dirs+files:
   path=os.path.join(current,name)
   if os.path.islink(path): raise SystemExit(1)
  for name in files:
   path=os.path.join(current,name); file_stat=os.lstat(path)
   if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_mode&0o400!=0o400: raise SystemExit(1)
   total+=file_stat.st_size; entries+=1
   if file_stat.st_size>256*1024*1024 or total>512*1024*1024 or entries>4096: raise SystemExit(1)
   relative=os.path.relpath(path,parent).replace(os.sep,'/')
   info=zipfile.ZipInfo(relative,stamp(file_stat.st_mtime)); info.create_system=3
   info.external_attr=(stat.S_IFREG|stat.S_IMODE(file_stat.st_mode))<<16
   info.compress_type=zipfile.ZIP_DEFLATED; info.extra=b''; info.comment=b''
   with archive.open(info,'w',force_zip64=False) as destination,open(path,'rb') as source:
    for chunk in iter(lambda:source.read(1024*1024),b''): destination.write(chunk)
if entries>4096: raise SystemExit(1)
PY
  then
    die 'ZIP producer failed'
  fi
}

archive_central_directory_is_safe_and_portable() {
  /usr/bin/python3 -I - "$1" "$2" <<'PY'
import binascii,os,posixpath,stat,struct,sys,unicodedata,zipfile,zlib
PER_ENTRY_LIMIT=256*1024*1024
TOTAL_LIMIT=512*1024*1024
if os.path.getsize(sys.argv[1])>512*1024*1024: raise SystemExit(1)
z=zipfile.ZipFile(sys.argv[1]); root=sys.argv[2]+'/'; seen=set(); casefolded=set(); infos=z.infolist()
if z.comment or any(i.comment or i.extra for i in infos): raise SystemExit(1)
if len(infos)>4096 or sum(i.file_size for i in infos)>TOTAL_LIMIT or sum(i.compress_size for i in infos)>TOTAL_LIMIT: raise SystemExit(1)
for i in infos:
 if i.filename!=i.orig_filename or '\x00' in i.orig_filename: raise SystemExit(1)
 p=i.orig_filename; n=unicodedata.normalize('NFC',p); parts=n.rstrip('/').split('/')
 key=n.rstrip('/').casefold(); directory=n.endswith('/')
 if not p or p!=n or '\x00' in p or '\n' in p or p.startswith('/') or '\\' in p or n in seen or key in casefolded or any(not part or part.startswith('._') for part in parts): raise SystemExit(1)
 if posixpath.normpath(n)!=n.rstrip('/') or n==root[:-1] or not n.startswith(root) or (directory and n.endswith('//')): raise SystemExit(1)
 seen.add(n); casefolded.add(key); mode=i.external_attr>>16; kind=stat.S_IFMT(mode)
 if stat.S_ISLNK(mode) or kind not in (stat.S_IFREG,stat.S_IFDIR) or (directory and kind!=stat.S_IFDIR) or (not directory and kind!=stat.S_IFREG) or mode&0o7022 or i.flag_bits&~0x800: raise SystemExit(1)
 if kind==stat.S_IFDIR and mode&0o500!=0o500 or kind==stat.S_IFREG and mode&0o400!=0o400: raise SystemExit(1)
 if i.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED) or i.file_size>PER_ENTRY_LIMIT or (i.file_size>1024*1024 and (i.compress_size==0 or i.file_size/i.compress_size>200)): raise SystemExit(1)
if root not in seen or root+'Contents/Info.plist' not in seen: raise SystemExit(1)

# Do not trust the central/local uncompressed-size fields.  Generic extractors
# follow the raw DEFLATE stream and can expand far beyond forged declarations.
# Re-read each local entry, validate any data descriptor, and count/CRC the
# actual stream output under independent per-entry and aggregate limits.
archive_size=os.path.getsize(sys.argv[1])
if archive_size<22: raise SystemExit(1)
with open(sys.argv[1],'rb') as stream:
 stream.seek(-22,os.SEEK_END); eocd_offset=stream.tell(); eocd_bytes=stream.read(22)
eocd=struct.unpack('<IHHHHIIH',eocd_bytes)
if eocd[0]!=0x06054B50: raise SystemExit(1)
if eocd[1]!=0 or eocd[2]!=0 or eocd[3]!=len(infos) or eocd[4]!=len(infos) or eocd[7]!=0: raise SystemExit(1)
central_size=eocd[5]; central_offset=eocd[6]
if central_offset+central_size!=eocd_offset or eocd_offset+22!=archive_size: raise SystemExit(1)
with open(sys.argv[1],'rb') as stream:
 stream.seek(central_offset)
 for i in infos:
  header=stream.read(46)
  if len(header)!=46: raise SystemExit(1)
  central=struct.unpack('<IHHHHHHIIIHHHHHII',header)
  if central[0]!=0x02014B50: raise SystemExit(1)
  name_len,extra_len,comment_len=central[10:13]
  raw_name=stream.read(name_len); raw_extra=stream.read(extra_len); raw_comment=stream.read(comment_len)
  if len(raw_name)!=name_len or raw_extra or raw_comment: raise SystemExit(1)
  encoding='utf-8' if central[3]&0x800 else 'cp437'
  try: decoded_name=raw_name.decode(encoding)
  except UnicodeDecodeError: raise SystemExit(1)
  if decoded_name!=i.orig_filename or '\x00' in decoded_name: raise SystemExit(1)
  if (central[3],central[4],central[7],central[8],central[9],central[15],central[16])!=(i.flag_bits,i.compress_type,i.CRC,i.compress_size,i.file_size,i.external_attr,i.header_offset): raise SystemExit(1)
  if central[13]!=0: raise SystemExit(1)
 if stream.tell()!=central_offset+central_size: raise SystemExit(1)
actual_total=0; expected_local_offset=0
with open(sys.argv[1],'rb') as stream:
 for i in infos:
  if i.header_offset!=expected_local_offset: raise SystemExit(1)
  stream.seek(i.header_offset)
  header=stream.read(30)
  if len(header)!=30: raise SystemExit(1)
  signature,version,flags,method,mtime,mdate,local_crc,local_csize,local_usize,name_len,extra_len=struct.unpack('<IHHHHHIIIHH',header)
  if signature!=0x04034B50 or flags!=i.flag_bits or method!=i.compress_type: raise SystemExit(1)
  local_name=stream.read(name_len)
  local_extra=stream.read(extra_len)
  if len(local_name)!=name_len or local_extra: raise SystemExit(1)
  encoding='utf-8' if flags&0x800 else 'cp437'
  try: decoded_name=local_name.decode(encoding)
  except UnicodeDecodeError: raise SystemExit(1)
  if decoded_name!=i.orig_filename: raise SystemExit(1)
  if (local_crc,local_csize,local_usize)!=(i.CRC,i.compress_size,i.file_size): raise SystemExit(1)
  remaining=i.compress_size; actual=0; crc=0
  decompressor=zlib.decompressobj(-15) if method==zipfile.ZIP_DEFLATED else None
  while remaining:
   chunk=stream.read(min(1024*1024,remaining))
   if not chunk: raise SystemExit(1)
   remaining-=len(chunk)
   pending=chunk
   while pending:
    if decompressor is None:
     output=pending; pending=b''
    else:
     allowance=min(1024*1024,PER_ENTRY_LIMIT+1-actual,TOTAL_LIMIT+1-actual_total)
     if allowance<=0: raise SystemExit(1)
     output=decompressor.decompress(pending,allowance)
     pending=decompressor.unconsumed_tail
    actual+=len(output); actual_total+=len(output); crc=binascii.crc32(output,crc)
    if actual>PER_ENTRY_LIMIT or actual_total>TOTAL_LIMIT: raise SystemExit(1)
  if decompressor is not None and (not decompressor.eof or decompressor.unused_data or decompressor.unconsumed_tail): raise SystemExit(1)
  if actual!=i.file_size or (crc&0xffffffff)!=i.CRC: raise SystemExit(1)
  expected_local_offset=stream.tell()
if expected_local_offset!=central_offset: raise SystemExit(1)
PY
}

release_test_evidence_is_valid() {
  local evidence_path="$1" expected_commit="$2"
  [[ "$evidence_path" == /* && -f "$evidence_path" && ! -L "$evidence_path" \
    && "${evidence_path##*/}" == "$release_test_evidence_name" ]] || return 1
  /usr/bin/python3 -I - "$evidence_path" "$expected_commit" <<'PY'
import datetime,json,os,re,sys
p,c=sys.argv[1:]
def reject_duplicates(pairs):
 out={}
 for key,value in pairs:
  if key in out: raise ValueError("duplicate JSON key")
  out[key]=value
 return out
try:
 if os.path.getsize(p)>32768: raise ValueError("oversized evidence")
 with open(p,encoding="utf-8") as stream:
  d=json.load(stream,object_pairs_hook=reject_duplicates)
except Exception:
 raise SystemExit(1)
claim="Automated source-candidate evidence only; no live PowerPoint, user acceptance, installation, publication, or public-redownload result is implied."
def exact(value, keys):
 return isinstance(value,dict) and set(value)==set(keys)
def integer(value, minimum=0):
 return type(value) is int and value>=minimum
if not exact(d,{"schema","sourceCommit","generatedAt","prepublicationGate","coreTests","nativeAppTests","environment","claimBoundary"}): raise SystemExit(1)
if d["schema"]!="lectureboard.release-test-evidence.v1" or d["sourceCommit"]!=c or d["claimBoundary"]!=claim: raise SystemExit(1)
if not isinstance(d["generatedAt"],str): raise SystemExit(1)
try:
 datetime.datetime.strptime(d["generatedAt"],"%Y-%m-%dT%H:%M:%SZ")
except ValueError:
 raise SystemExit(1)
g=d["prepublicationGate"]
if not exact(g,{"command","result","passedStages","totalStages","logSha256","scriptBlobOid"}) or g["command"]!="./scripts/prepublish-check.sh" or g["result"]!="Passed" or g["passedStages"]!=26 or g["totalStages"]!=26: raise SystemExit(1)
if not isinstance(g["logSha256"],str) or not re.fullmatch(r"[0-9a-f]{64}",g["logSha256"]) or g["logSha256"]=="0"*64: raise SystemExit(1)
blob=g["scriptBlobOid"]
if not isinstance(blob,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",blob) or blob in {"0"*40,"0"*64} or len(blob)!=len(c): raise SystemExit(1)
core=d["coreTests"]
if not exact(core,{"result","tests","suites","failed","skipped"}) or core["result"]!="Passed" or any(not integer(core[key]) for key in ("tests","suites","failed","skipped")) or (core["tests"],core["suites"],core["failed"],core["skipped"])!=(248,19,0,0): raise SystemExit(1)
native=d["nativeAppTests"]
native_keys={"result","authoritativeTests","deviceRuns","parameterizedTests","parameterizedRuns","failed","skipped","expectedFailures","resultBundleName","resultBundleTreeSha256"}
if not exact(native,native_keys) or native["result"]!="Passed" or any(not integer(native[key]) for key in native_keys-{"result","resultBundleName","resultBundleTreeSha256"}) or native["authoritativeTests"]<1 or native["deviceRuns"]<native["authoritativeTests"] or native["parameterizedRuns"]<native["parameterizedTests"]: raise SystemExit(1)
if native["failed"]!=0 or native["skipped"]!=0 or native["expectedFailures"]!=0: raise SystemExit(1)
if native["deviceRuns"]!=native["authoritativeTests"]+native["parameterizedRuns"]-native["parameterizedTests"]: raise SystemExit(1)
if (native["authoritativeTests"],native["deviceRuns"],native["parameterizedTests"],native["parameterizedRuns"])!=(480,542,14,76): raise SystemExit(1)
name=native["resultBundleName"]
if not isinstance(name,str) or os.path.basename(name)!=name or not re.fullmatch(r"Test-LectureBoardAI-[0-9._+-]+\.xcresult",name): raise SystemExit(1)
if not isinstance(native["resultBundleTreeSha256"],str) or not re.fullmatch(r"[0-9a-f]{64}",native["resultBundleTreeSha256"]) or native["resultBundleTreeSha256"]=="0"*64: raise SystemExit(1)
env=d["environment"]
if not exact(env,{"architecture","macOS","macOSBuild","xcode","xcodeBuild"}) or env["architecture"]!="arm64": raise SystemExit(1)
patterns={"macOS":r"[0-9]+(?:\.[0-9]+){1,2}","macOSBuild":r"[0-9A-Za-z]+","xcode":r"[0-9]+(?:\.[0-9]+){1,2}","xcodeBuild":r"[0-9A-Za-z]+"}
for key,pattern in patterns.items():
 if not isinstance(env[key],str) or not re.fullmatch(pattern,env[key]): raise SystemExit(1)
PY
}

native_result_summary_is_valid() {
  /usr/bin/python3 -I - "$@" <<'PY'
import datetime,json,re,sys
evidence_path,summary_path,build_path,action_path,expected_commit,macos_version,macos_build,xcode_version,xcode_build=sys.argv[1:]
with open(evidence_path,encoding="utf-8") as stream:
 evidence=json.load(stream)
with open(summary_path,encoding="utf-8") as stream:
 summary=json.load(stream)
with open(build_path,encoding="utf-8") as stream:
 build=json.load(stream)
with open(action_path,encoding="utf-8") as stream:
 action=json.load(stream)
native=evidence["nativeAppTests"]
environment=evidence["environment"]
def integer(value):
 return type(value) is int and value>=0
if environment!={"architecture":"arm64","macOS":macos_version,"macOSBuild":macos_build,"xcode":xcode_version,"xcodeBuild":xcode_build}: raise SystemExit(1)
if any(not integer(summary.get(key)) for key in ("failedTests","skippedTests","expectedFailures","passedTests","totalTestCount")): raise SystemExit(1)
if summary.get("title")!="Test - LectureBoardAI" or summary.get("result")!="Passed" or summary.get("failedTests")!=0 or summary.get("skippedTests")!=0 or summary.get("expectedFailures")!=0: raise SystemExit(1)
start=summary.get("startTime"); finish=summary.get("finishTime")
if type(start) not in (int,float) or type(finish) not in (int,float) or start<=0 or finish<start: raise SystemExit(1)
try: generated=datetime.datetime.strptime(evidence["generatedAt"],"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
except (KeyError,TypeError,ValueError): raise SystemExit(1)
if finish>generated+1 or generated-finish>6*60*60: raise SystemExit(1)
if summary.get("passedTests")!=native["authoritativeTests"] or summary.get("totalTestCount")!=native["authoritativeTests"]: raise SystemExit(1)
devices=summary.get("devicesAndConfigurations")
if not isinstance(devices,list) or len(devices)!=1: raise SystemExit(1)
device_result=devices[0]
device=device_result.get("device")
if not isinstance(device,dict) or device.get("architecture")!="arm64" or device.get("osVersion")!=macos_version or device.get("osBuildNumber")!=macos_build or device.get("platform")!="macOS": raise SystemExit(1)
if any(not integer(device_result.get(key)) for key in ("passedTests","failedTests","skippedTests","expectedFailures")): raise SystemExit(1)
if device_result.get("passedTests")!=native["deviceRuns"] or device_result.get("failedTests")!=0 or device_result.get("skippedTests")!=0 or device_result.get("expectedFailures")!=0: raise SystemExit(1)
statistics=summary.get("statistics")
if not isinstance(statistics,list): raise SystemExit(1)
matches=[]
for item in statistics:
 if not isinstance(item,dict): continue
 title=re.fullmatch(r"([0-9]+) tests ran with dynamic parameters",item.get("title", ""))
 subtitle=re.fullmatch(r"([0-9]+) test runs",item.get("subtitle", ""))
 if title and subtitle: matches.append((int(title.group(1)),int(subtitle.group(1))))
if matches!=[(native["parameterizedTests"],native["parameterizedRuns"])]: raise SystemExit(1)
if build.get("actionTitle")!="Testing project LectureBoardAI with scheme LectureBoardAI" or build.get("status")!="succeeded" or type(build.get("errorCount")) is not int or build["errorCount"]!=0: raise SystemExit(1)
if build.get("startTime")!=start or build.get("endTime")!=finish: raise SystemExit(1)
destination=build.get("destination")
if not isinstance(destination,dict) or destination.get("architecture")!="arm64" or destination.get("platform")!="macOS" or destination.get("osVersion")!=macos_version or destination.get("osBuildNumber")!=macos_build: raise SystemExit(1)
reported=[]
def collect(value):
 if isinstance(value,dict):
  for key,item in value.items():
   if key=="emittedOutput" and isinstance(item,str):
    reported.extend(re.findall(r"(?m)^LectureBoard native-test embedded source commit: ([0-9a-f]{40}|[0-9a-f]{64})\r?$",item))
   collect(item)
 elif isinstance(value,list):
  for item in value: collect(item)
collect(action)
if not reported or set(reported)!={expected_commit}: raise SystemExit(1)
PY
}

release_gate_log_matches() {
  local evidence_path="$1" gate_log="$2" expected_digest
  bounded_regular "$gate_log" gate-log 16777216 || return 1
  expected_digest="$(/usr/bin/plutil -extract prepublicationGate.logSha256 raw -o - "$evidence_path" 2>/dev/null)" \
    || return 1
  [[ "$(sha256 "$gate_log")" == "$expected_digest" ]] || return 1
  /usr/bin/python3 -I - "$gate_log" "$evidence_path" <<'PY'
import json,re,sys
try:
 data=open(sys.argv[1],encoding="utf-8",errors="strict").read()
 evidence=json.load(open(sys.argv[2],encoding="utf-8"))
except Exception:
 raise SystemExit(1)
if len(data)>16*1024*1024 or "Prepublication checks passed. Manual institutional IP and privacy review is still required." not in data:
 raise SystemExit(1)
stages=[int(value) for value in re.findall(r"(?m)^\[([0-9]+)/26\] ",data)]
if stages!=list(range(1,27)):
 raise SystemExit(1)
matches=re.findall(r"(?m)^[^\n]*Test run with 248 tests in 19 suites passed[^\n]*$",data)
if len(matches)!=1:
 raise SystemExit(1)
commit=evidence.get("sourceCommit")
lines=data.splitlines()
if not isinstance(commit,str) or not lines or lines[0]!="LectureBoard evidence transaction source commit: "+commit or lines[-1]!="LectureBoard evidence transaction completed for source commit: "+commit:
 raise SystemExit(1)
PY
}

release_gate_script_matches_commit() {
  local evidence_path="$1" source_root="$2" expected_commit="$3"
  local expected_blob actual_blob
  expected_blob="$(/usr/bin/plutil -extract prepublicationGate.scriptBlobOid raw -o - \
    "$evidence_path" 2>/dev/null)" || return 1
  actual_blob="$(git_read -C "$source_root" rev-parse \
    "$expected_commit:scripts/prepublish-check.sh")" || return 1
  [[ "$expected_blob" == "$actual_blob" ]]
}

write_release_test_evidence() {
  local destination="$1" expected_commit="$2" gate_log="$3" result_bundle="$4" source_root="$5"
  local expected_result_digest="$6"
  local result_digest summary_path build_path action_path macos_version macos_build xcode_version xcode_build
  local generated_at gate_log_digest gate_script_blob_oid
  [[ "$expected_result_digest" =~ ^[0-9a-f]{64}$ ]] \
    || die 'result-bundle digest is malformed'
  result_digest="$expected_result_digest"
  summary_path="$temp/native-summary.json"
  build_path="$temp/native-build.json"
  action_path="$temp/native-action.json"
  extract_result_bundle_query_outputs "$result_bundle" "$source_root" "$result_digest" \
    "$summary_path" "$build_path" "$action_path" \
    || die 'native result queries could not be generated without mutating the authoritative bundle'
  macos_version="$(/usr/bin/sw_vers -productVersion)" \
    || die 'macOS version could not be read'
  macos_build="$(/usr/bin/sw_vers -buildVersion)" \
    || die 'macOS build could not be read'
  xcode_version="$(/usr/bin/xcodebuild -version | /usr/bin/awk 'NR == 1 { print $2 }')" \
    || die 'Xcode version could not be read'
  xcode_build="$(/usr/bin/xcodebuild -version | /usr/bin/awk 'NR == 2 { print $3 }')" \
    || die 'Xcode build could not be read'
  generated_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    || die 'test-evidence creation time unavailable'
  gate_log_digest="$(sha256 "$gate_log")"
  gate_script_blob_oid="$(git_read -C "$source_root" rev-parse \
    "$expected_commit:scripts/prepublish-check.sh")" \
    || die 'prepublication gate blob identity unavailable'
  oid "$gate_script_blob_oid" prepublication-gate-blob
  /usr/bin/python3 -I - "$destination" "$expected_commit" "$generated_at" \
    "$gate_log_digest" "$gate_script_blob_oid" "$result_bundle" "$result_digest" "$summary_path" \
    "$macos_version" "$macos_build" "$xcode_version" "$xcode_build" <<'PY'
import json,re,sys
(destination,commit,generated,log_digest,script_blob,result_bundle,result_digest,summary_path,
 macos_version,macos_build,xcode_version,xcode_build)=sys.argv[1:]
summary=json.load(open(summary_path,encoding="utf-8"))
devices=summary.get("devicesAndConfigurations")
if not isinstance(devices,list) or len(devices)!=1: raise SystemExit(1)
device=devices[0]
statistics=summary.get("statistics")
matches=[]
if isinstance(statistics,list):
 for item in statistics:
  if not isinstance(item,dict): continue
  title=re.fullmatch(r"([0-9]+) tests ran with dynamic parameters",item.get("title",""))
  subtitle=re.fullmatch(r"([0-9]+) test runs",item.get("subtitle",""))
  if title and subtitle: matches.append((int(title.group(1)),int(subtitle.group(1))))
if len(matches)!=1: raise SystemExit(1)
parameterized_tests,parameterized_runs=matches[0]
evidence={
 "schema":"lectureboard.release-test-evidence.v1",
 "sourceCommit":commit,
 "generatedAt":generated,
 "prepublicationGate":{"command":"./scripts/prepublish-check.sh","result":"Passed","passedStages":26,"totalStages":26,"logSha256":log_digest,"scriptBlobOid":script_blob},
 "coreTests":{"result":"Passed","tests":248,"suites":19,"failed":0,"skipped":0},
 "nativeAppTests":{
  "result":summary.get("result"),"authoritativeTests":summary.get("totalTestCount"),
  "deviceRuns":device.get("passedTests"),"parameterizedTests":parameterized_tests,
  "parameterizedRuns":parameterized_runs,"failed":summary.get("failedTests"),
  "skipped":summary.get("skippedTests"),"expectedFailures":summary.get("expectedFailures"),
  "resultBundleName":result_bundle.rsplit("/",1)[-1],"resultBundleTreeSha256":result_digest},
 "environment":{"architecture":"arm64","macOS":macos_version,"macOSBuild":macos_build,"xcode":xcode_version,"xcodeBuild":xcode_build},
 "claimBoundary":"Automated source-candidate evidence only; no live PowerPoint, user acceptance, installation, publication, or public-redownload result is implied."
}
with open(destination,"x",encoding="utf-8") as stream:
 json.dump(evidence,stream,ensure_ascii=True,sort_keys=True,separators=(",",":"))
 stream.write("\n")
PY
  generated_evidence_digest="$(sha256 "$destination")" \
    || die 'generated release test-evidence digest could not be captured'
  [[ "$generated_evidence_digest" =~ ^[0-9a-f]{64}$ ]] \
    || die 'generated release test-evidence digest is malformed'
  release_test_evidence_is_valid "$destination" "$expected_commit" \
    || die 'generated release test evidence is invalid'
  release_gate_log_matches "$destination" "$gate_log" \
    || die 'generated release test evidence does not match its gate log'
  release_gate_script_matches_commit "$destination" "$source_root" "$expected_commit" \
    || die 'generated release test evidence does not match the committed gate script'
  native_result_summary_is_valid "$destination" "$summary_path" "$build_path" \
    "$action_path" "$expected_commit" "$macos_version" "$macos_build" \
    "$xcode_version" "$xcode_build" \
    || die 'generated release test evidence does not match the disposable result queries'
  regular_file_matches_sha256 "$destination" "$generated_evidence_digest" \
    || die 'generated release test evidence changed while it was being validated'
}

result_bundle_tree_digest() {
  local result_bundle="$1" source_root="$2" manifest_root manifest_path digest status=0
  [[ "$result_bundle" == /* && -d "$result_bundle" && ! -L "$result_bundle" ]] || return 1
  [[ "$source_root" == /* && -d "$source_root" && ! -L "$source_root" ]] || return 1
  [[ -z "$(/usr/bin/find "$result_bundle" -type l -print -quit)" ]] || return 1
  [[ -z "$(/usr/bin/find "$result_bundle" \
    \( -type b -o -type c -o -type p -o -type s \) -print -quit)" ]] || return 1
  regular "$source_root/scripts/release-artifact-tools.sh" result-bundle-manifest-tool
  manifest_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-result-bundle-manifest.XXXXXX)" \
    || return 1
  manifest_path="$manifest_root/result-bundle.tree"
  if ! /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
    /bin/bash -p "$source_root/scripts/release-artifact-tools.sh" tree-manifest \
      --root "$result_bundle" --output "$manifest_path"; then
    status=1
  elif ! digest="$(sha256 "$manifest_path")"; then
    status=1
  fi
  /usr/bin/find "$manifest_root" -depth -delete || status=1
  [[ "$status" == 0 ]] || return 1
  /usr/bin/printf '%s\n' "$digest"
}

result_bundle_pair_matches_digest() {
  local first="$1" second="$2" source_root="$3" expected_digest="$4"
  local expected_first_token="${5:-}"
  local digest_root first_path second_path first_pid second_pid
  local first_status=0 second_status=0 first_digest='' second_digest=''
  local first_identity second_identity first_token_before second_token_before
  local first_token_after second_token_after digest_parent_identity digest_root_identity status=0
  [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ -z "$expected_first_token" || "$expected_first_token" =~ ^[0-9a-f]{64}$ ]] \
    || return 1
  first_identity="$(directory_identity "$first")" || return 1
  second_identity="$(directory_identity "$second")" || return 1
  first_token_before="$(result_bundle_stability_token "$first")" || return 1
  second_token_before="$(result_bundle_stability_token "$second")" || return 1
  [[ -z "$expected_first_token" || "$first_token_before" == "$expected_first_token" ]] \
    || return 1
  [[ "$(directory_identity "$first")" == "$first_identity" \
    && "$(directory_identity "$second")" == "$second_identity" ]] || return 1
  digest_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-result-pair.XXXXXX)" \
    || return 1
  digest_parent_identity="$(directory_identity /private/tmp)" || return 1
  digest_root_identity="$(directory_identity "$digest_root")" || return 1
  first_path="$digest_root/first.sha256"
  second_path="$digest_root/second.sha256"
  (result_bundle_tree_digest "$first" "$source_root" >"$first_path") &
  first_pid=$!
  (result_bundle_tree_digest "$second" "$source_root" >"$second_path") &
  second_pid=$!
  wait "$first_pid" || first_status=$?
  wait "$second_pid" || second_status=$?
  if [[ "$first_status" != 0 || "$second_status" != 0 \
    || "$(/usr/bin/awk 'END { print NR + 0 }' "$first_path")" != 1 \
    || "$(/usr/bin/awk 'END { print NR + 0 }' "$second_path")" != 1 ]]; then
    status=1
  else
    IFS= read -r first_digest <"$first_path" || status=1
    IFS= read -r second_digest <"$second_path" || status=1
    [[ "$first_digest" == "$expected_digest" \
      && "$second_digest" == "$expected_digest" ]] || status=1
  fi
  second_token_after="$(result_bundle_stability_token "$second")" || status=1
  first_token_after="$(result_bundle_stability_token "$first")" || status=1
  [[ "$(directory_identity "$first")" == "$first_identity" \
    && "$(directory_identity "$second")" == "$second_identity" \
    && "$first_token_after" == "$first_token_before" \
    && "$second_token_after" == "$second_token_before" ]] || status=1
  delete_directory_with_identity /private/tmp "$digest_parent_identity" \
    "$digest_root" "$digest_root_identity" || status=1
  [[ "$status" == 0 ]]
}

result_bundle_stability_pause() {
  /bin/sleep 1
}

result_bundle_set_monotonic_now() {
  local seconds_value="${SECONDS-}"
  [[ "$seconds_value" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  (( ${#seconds_value} <= 10 )) || return 1
  (( seconds_value <= 9223372036 )) || return 1
  monotonic_now=$((seconds_value * 1000000000))
  [[ "$monotonic_now" =~ ^[0-9]+$ ]] \
    && (( monotonic_now / 1000000000 == seconds_value ))
}

result_bundle_stability_token() {
  local result_bundle="$1" test_mutate_relative='' test_trigger_relative=''
  if (( $# != 1 )); then
    [[ $# == 3 && "${LECTUREBOARD_RELEASE_TEST_MODE:-}" == 1 ]] || return 1
    test_mutate_relative="$2"
    test_trigger_relative="$3"
  fi
  /usr/bin/python3 -I - "$result_bundle" "$test_mutate_relative" "$test_trigger_relative" <<'PY'
import hashlib,os,stat,struct,sys
root,mutate_relative,trigger_relative=sys.argv[1:]
if not os.path.isabs(root) or not os.path.isdir(root) or os.path.islink(root): raise SystemExit(1)
h=hashlib.sha256()
def field(value):
 data=value if isinstance(value,bytes) else str(value).encode('utf-8','surrogateescape')
 h.update(struct.pack('>Q',len(data))); h.update(data)
def identity(value):
 return (value.st_dev,value.st_ino,value.st_mode,value.st_uid,value.st_gid,value.st_size,
         value.st_mtime_ns,value.st_ctime_ns,getattr(value,'st_flags',0))
root_before=os.lstat(root)
if not stat.S_ISDIR(root_before.st_mode): raise SystemExit(1)
relative_paths=['.']
for current,dirs,files in os.walk(root,topdown=True,followlinks=False):
 dirs.sort(); files.sort()
 for name in dirs+files:
  path=os.path.join(current,name); value=os.lstat(path)
  if stat.S_ISLNK(value.st_mode) or not (stat.S_ISDIR(value.st_mode) or stat.S_ISREG(value.st_mode)):
   raise SystemExit(1)
  relative_paths.append(os.path.relpath(path,root))
relative_paths=sorted(relative_paths)
if bool(mutate_relative)!=bool(trigger_relative): raise SystemExit(1)
if mutate_relative:
 if (mutate_relative not in relative_paths or trigger_relative not in relative_paths
     or relative_paths.index(mutate_relative)>=relative_paths.index(trigger_relative)):
  raise SystemExit(1)
identities={}
test_mutated=False
for relative in relative_paths:
 path=root if relative=='.' else os.path.join(root,relative)
 before=os.lstat(path); identities[relative]=identity(before)
 field(relative); field(identity(before))
 if stat.S_ISREG(before.st_mode):
  content=hashlib.sha256()
  with open(path,'rb') as stream:
   first_chunk=True
   for chunk in iter(lambda:stream.read(1024*1024),b''):
    if mutate_relative and relative==trigger_relative and first_chunk:
     mutate_path=os.path.join(root,mutate_relative)
     mutate_status=os.lstat(mutate_path)
     if not stat.S_ISREG(mutate_status.st_mode): raise SystemExit(1)
     with open(mutate_path,'ab') as mutation: mutation.write(b'\nmid-token-test-mutation\n')
     test_mutated=True
    first_chunk=False
    content.update(chunk)
  field(content.digest())
 after=os.lstat(path)
 if identity(before)!=identity(after): raise SystemExit(1)
if mutate_relative and not test_mutated: raise SystemExit(1)
final_relative_paths=['.']
for current,dirs,files in os.walk(root,topdown=True,followlinks=False):
 dirs.sort(); files.sort()
 for name in dirs+files:
  path=os.path.join(current,name); value=os.lstat(path)
  if stat.S_ISLNK(value.st_mode) or not (stat.S_ISDIR(value.st_mode) or stat.S_ISREG(value.st_mode)):
   raise SystemExit(1)
  final_relative_paths.append(os.path.relpath(path,root))
final_relative_paths=sorted(final_relative_paths)
if final_relative_paths!=relative_paths: raise SystemExit(1)
for relative in final_relative_paths:
 path=root if relative=='.' else os.path.join(root,relative)
 if identity(os.lstat(path))!=identities[relative]: raise SystemExit(1)
print(h.hexdigest())
PY
}

copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2"
}

run_result_bundle_queries() {
  local result_bundle="$1" summary_path="$2" build_path="$3" action_path="$4"
  /usr/bin/xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --format json >"$summary_path" \
    && /usr/bin/xcrun xcresulttool get build-results \
      --path "$result_bundle" --format json >"$build_path" \
    && /usr/bin/xcrun xcresulttool get log --type action \
      --path "$result_bundle" --compact >"$action_path"
}

extract_result_bundle_query_outputs() {
  local result_bundle="$1" source_root="$2" expected_digest="$3"
  local summary_path="$4" build_path="$5" action_path="$6"
  local query_root query_bundle source_identity query_identity current_identity source_token
  local final_source_digest final_source_token query_parent_identity query_root_identity status=0
  [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ "$result_bundle" == /* && -d "$result_bundle" && ! -L "$result_bundle" ]] \
    || return 1
  [[ "$summary_path" == /* && "$build_path" == /* && "$action_path" == /* \
    && ! -e "$summary_path" && ! -L "$summary_path" \
    && ! -e "$build_path" && ! -L "$build_path" \
    && ! -e "$action_path" && ! -L "$action_path" ]] || return 1
  source_identity="$(directory_identity "$result_bundle")" || return 1
  source_token="$(result_bundle_stability_token "$result_bundle")" || return 1
  query_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-result-query.XXXXXX)" \
    || return 1
  query_parent_identity="$(directory_identity /private/tmp)" || return 1
  query_root_identity="$(directory_identity "$query_root")" || return 1
  query_bundle="$query_root/${result_bundle##*/}"
  if ! /usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$query_bundle"; then
    status=1
  elif ! current_identity="$(directory_identity "$result_bundle")" \
    || [[ "$current_identity" != "$source_identity" ]] \
    || ! query_identity="$(directory_identity "$query_bundle")"; then
    status=1
  elif ! result_bundle_pair_matches_digest \
    "$result_bundle" "$query_bundle" "$source_root" "$expected_digest" "$source_token"; then
    status=1
  fi
  if [[ "$status" == 0 ]] && ! run_result_bundle_queries "$query_bundle" \
    "$summary_path" "$build_path" "$action_path"; then
    status=1
  elif [[ "$status" == 0 ]] && { ! regular "$summary_path" result-summary \
    || ! regular "$build_path" result-build \
    || ! regular "$action_path" result-action \
    || [[ "$(directory_identity "$query_bundle")" != "$query_identity" ]] \
    || [[ "$(directory_identity "$result_bundle")" != "$source_identity" ]] \
    || ! final_source_digest="$(result_bundle_tree_digest "$result_bundle" "$source_root")" \
    || ! final_source_token="$(result_bundle_stability_token "$result_bundle")" \
    || [[ "$final_source_digest" != "$expected_digest" \
      || "$final_source_token" != "$source_token" ]]; }; then
    status=1
  fi
  delete_directory_with_identity /private/tmp "$query_parent_identity" \
    "$query_root" "$query_root_identity" || status=1
  [[ "$status" == 0 ]]
}

freeze_result_bundle_when_stable() {
  local result_bundle="$1" destination="$2" source_root="$3"
  local destination_parent destination_parent_physical destination_leaf
  local source_identity parent_identity current_identity current_parent_identity destination_identity
  local current_token='' previous_token='' post_digest_token=''
  local destination_token='' post_pair_source_token='' post_pair_destination_token=''
  local current_digest=''
  local stable_observations=0 observation=0 copy_attempts=0 monotonic_now=0
  local pair_digest_matches=0 final_seal_failure=''
  local stable_since=0 started_at=0 deadline=0
  local required_stable_observations=6 quiet_nanoseconds=5000000000
  local maximum_observations=600 maximum_copy_attempts=2 deadline_nanoseconds=600000000000
  [[ "$result_bundle" == /* && -d "$result_bundle" && ! -L "$result_bundle" ]] \
    || return 1
  frozen_result_bundle_digest=''
  [[ "$destination" == /* && "$destination" != / && ! -e "$destination" \
    && ! -L "$destination" ]] || return 1
  destination_parent="$(/usr/bin/dirname -- "$destination")" || return 1
  destination_leaf="${destination##*/}"
  [[ -n "$destination_leaf" && -d "$destination_parent" \
    && ! -L "$destination_parent" ]] || return 1
  destination_parent_physical="$(cd -- "$destination_parent" && /bin/pwd -P)" \
    || return 1
  [[ "$destination" == "$destination_parent_physical/$destination_leaf" ]] \
    || return 1
  source_identity="$(directory_identity "$result_bundle")" || return 1
  parent_identity="$(directory_identity "$destination_parent_physical")" || return 1
  result_bundle_set_monotonic_now || return 1
  started_at="$monotonic_now"
  (( monotonic_now <= 9223371436854775807 )) || return 1
  deadline=$((monotonic_now + deadline_nanoseconds))
  /usr/bin/printf \
    'release evidence result freeze: phase=stabilityWaiting observation=0 copyAttempt=0 elapsedSeconds=0\n' \
    >&2

  # xcodebuild can return before its xcresult service has completed the last
  # bundle writes.  Require a five-second quiet window using an inexpensive
  # whole-tree token, then retain the canonical copy-before/source-after/copy
  # digest equality as the TOCTOU gate.  The token is never release evidence.
  # A mutation during the copy discards that copy and restarts stabilization;
  # root or destination-parent replacement always fails closed.
  while (( observation < maximum_observations )); do
    observation=$((observation + 1))
    result_bundle_set_monotonic_now || return 1
    if (( monotonic_now > deadline )); then
      /usr/bin/printf \
        'release evidence result freeze: failure=deadlineExceeded observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
        "$observation" "$copy_attempts" \
        "$(((monotonic_now - started_at) / 1000000000))" >&2
      return 1
    fi
    current_identity="$(directory_identity "$result_bundle")" || return 1
    current_parent_identity="$(directory_identity "$destination_parent_physical")" \
      || return 1
    [[ "$current_identity" == "$source_identity" \
      && "$current_parent_identity" == "$parent_identity" ]] || return 1
    if current_token="$(result_bundle_stability_token "$result_bundle")" \
      && [[ "$(directory_identity "$result_bundle")" == "$source_identity" \
        && "$(directory_identity "$destination_parent_physical")" == "$parent_identity" ]]; then
      result_bundle_set_monotonic_now || return 1
      if (( monotonic_now > deadline )); then
        /usr/bin/printf \
          'release evidence result freeze: failure=deadlineExceeded observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        return 1
      fi
      if [[ -n "$previous_token" && "$current_token" == "$previous_token" ]]; then
        stable_observations=$((stable_observations + 1))
      else
        previous_token="$current_token"
        stable_observations=1
        stable_since="$monotonic_now"
      fi
    else
      previous_token=''
      stable_observations=0
      stable_since=0
    fi

    if (( stable_observations >= required_stable_observations \
      && monotonic_now - stable_since >= quiet_nanoseconds )); then
      [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
      current_identity="$(directory_identity "$result_bundle")" || return 1
      current_parent_identity="$(directory_identity "$destination_parent_physical")" \
        || return 1
      [[ "$current_identity" == "$source_identity" \
        && "$current_parent_identity" == "$parent_identity" ]] || return 1
      /usr/bin/printf \
        'release evidence result freeze: phase=sourceDigestStarted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
        "$observation" "$copy_attempts" \
        "$(((monotonic_now - started_at) / 1000000000))" >&2
      if ! current_digest="$(result_bundle_tree_digest "$result_bundle" "$source_root")"; then
        /usr/bin/printf \
          'release evidence result freeze: retry=sourceDigestFailed observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        previous_token=''
        stable_observations=0
        stable_since=0
        continue
      fi
      result_bundle_set_monotonic_now || return 1
      /usr/bin/printf \
        'release evidence result freeze: phase=sourceDigestCompleted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
        "$observation" "$copy_attempts" \
        "$(((monotonic_now - started_at) / 1000000000))" >&2
      if (( monotonic_now > deadline )); then
        /usr/bin/printf \
          'release evidence result freeze: failure=deadlineExceeded observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        return 1
      fi
      if ! post_digest_token="$(result_bundle_stability_token "$result_bundle")"; then
        /usr/bin/printf \
          'release evidence result freeze: retry=postDigestTokenUnavailable observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        previous_token=''
        stable_observations=0
        stable_since=0
        continue
      fi
      [[ "$(directory_identity "$result_bundle")" == "$source_identity" \
        && "$(directory_identity "$destination_parent_physical")" == "$parent_identity" ]] \
        || return 1
      if [[ "$post_digest_token" != "$current_token" ]]; then
        /usr/bin/printf \
          'release evidence result freeze: retry=postDigestTokenChanged observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        previous_token="$post_digest_token"
        stable_observations=1
        result_bundle_set_monotonic_now || return 1
        stable_since="$monotonic_now"
        continue
      fi
      copy_attempts=$((copy_attempts + 1))
      if (( copy_attempts > maximum_copy_attempts )); then
        /usr/bin/printf \
          'release evidence result freeze: failure=copyAttemptsExhausted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        return 1
      fi
      /usr/bin/printf \
        'release evidence result freeze: phase=copyStarted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
        "$observation" "$copy_attempts" \
        "$(((monotonic_now - started_at) / 1000000000))" >&2
      if ! copy_result_bundle_for_freeze "$result_bundle" "$destination"; then
        # A failed copier does not establish which inode, if any, now occupies
        # the destination name.  Leave it inside the known staging directory;
        # its parent transaction can remove that directory by captured inode.
        /usr/bin/printf \
          'release evidence result freeze: failure=copyFailed observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        return 1
      fi
      destination_identity="$(directory_identity "$destination")" || return 1
      destination_token="$(result_bundle_stability_token "$destination")" || return 1
      current_identity="$(directory_identity "$result_bundle")" || return 1
      current_parent_identity="$(directory_identity "$destination_parent_physical")" \
        || return 1
      pair_digest_matches=0
      final_seal_failure=''
      /usr/bin/printf \
        'release evidence result freeze: phase=pairDigestStarted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
        "$observation" "$copy_attempts" \
        "$(((monotonic_now - started_at) / 1000000000))" >&2
      if [[ "$current_identity" == "$source_identity" \
          && "$current_parent_identity" == "$parent_identity" \
          && "$(directory_identity "$result_bundle")" == "$source_identity" \
          && "$(directory_identity "$destination_parent_physical")" == "$parent_identity" \
          && "$(directory_identity "$destination")" == "$destination_identity" \
          && "$current_digest" =~ ^[0-9a-f]{64}$ ]] \
        && result_bundle_pair_matches_digest \
          "$result_bundle" "$destination" "$source_root" "$current_digest" \
          "$post_digest_token"; then
        pair_digest_matches=1
      fi
      result_bundle_set_monotonic_now || return 1
      /usr/bin/printf \
        'release evidence result freeze: phase=pairDigestCompleted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
        "$observation" "$copy_attempts" \
        "$(((monotonic_now - started_at) / 1000000000))" >&2
      if [[ "$pair_digest_matches" == 1 ]] && (( monotonic_now <= deadline )); then
        current_identity="$(directory_identity "$result_bundle")" || return 1
        current_parent_identity="$(directory_identity "$destination_parent_physical")" \
          || return 1
        [[ "$current_identity" == "$source_identity" \
          && "$current_parent_identity" == "$parent_identity" ]] || return 1
        [[ -d "$destination" && ! -L "$destination" \
          && "$(directory_identity "$destination")" == "$destination_identity" \
          && "$(directory_identity "$destination_parent_physical")" == "$parent_identity" ]] \
          || return 1
        /usr/bin/printf \
          'release evidence result freeze: phase=finalSealStarted observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        if ! post_pair_destination_token="$(result_bundle_stability_token "$destination")"; then
          final_seal_failure='destinationTokenUnavailable'
        elif [[ "$post_pair_destination_token" != "$destination_token" ]]; then
          final_seal_failure='finalTokenMismatch'
        elif ! post_pair_source_token="$(result_bundle_stability_token "$result_bundle")"; then
          final_seal_failure='sourceTokenUnavailable'
        elif [[ "$post_pair_source_token" == "$post_digest_token" ]]; then
          frozen_result_bundle_digest="$current_digest"
          return 0
        else
          final_seal_failure='finalTokenMismatch'
        fi
        /usr/bin/printf \
          'release evidence result freeze: retry=%s observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$final_seal_failure" "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
      elif [[ "$pair_digest_matches" == 1 ]]; then
        /usr/bin/printf \
          'release evidence result freeze: failure=pairConsistentButDeadlineExceeded observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
      else
        /usr/bin/printf \
          'release evidence result freeze: retry=pairDigestMismatch observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
      fi
      [[ "$current_identity" == "$source_identity" \
        && "$current_parent_identity" == "$parent_identity" ]] || return 1
      [[ -d "$destination" && ! -L "$destination" \
        && "$(directory_identity "$destination")" == "$destination_identity" \
        && "$(directory_identity "$destination_parent_physical")" == "$parent_identity" ]] \
        || return 1
      delete_directory_with_identity "$destination_parent_physical" "$parent_identity" \
        "$destination" "$destination_identity" || return 1
      [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
      if [[ "$pair_digest_matches" == 1 ]] && (( monotonic_now > deadline )); then
        return 1
      fi
      if (( monotonic_now > deadline )); then
        /usr/bin/printf \
          'release evidence result freeze: failure=deadlineExceeded observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
          "$observation" "$copy_attempts" \
          "$(((monotonic_now - started_at) / 1000000000))" >&2
        return 1
      fi
      previous_token=''
      stable_observations=0
      stable_since=0
    fi
    if (( observation < maximum_observations )); then
      result_bundle_stability_pause || return 1
    fi
  done
  [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
  /usr/bin/printf \
    'release evidence result freeze: failure=observationLimitExceeded observation=%s copyAttempt=%s elapsedSeconds=%s\n' \
    "$observation" "$copy_attempts" \
    "$(((monotonic_now - started_at) / 1000000000))" >&2
  return 1
}

create_isolated_commit_source() {
  local repository="$1" expected_commit="$2" destination="$3"
  [[ "$destination" == /* && ! -e "$destination" && ! -L "$destination" ]] \
    || die 'isolated evidence destination is invalid'
  if commit_contains_git_attributes "$repository" "$expected_commit"; then
    die 'tracked Git attributes are not allowed for isolated release checkout'
    return 1
  fi
  git_read clone --no-local --no-hardlinks --no-checkout --no-tags -- \
    "$repository" "$destination" >/dev/null \
    || die 'isolated evidence clone could not be created'
  git_read -C "$destination" checkout --detach "$expected_commit" >/dev/null \
    || die 'isolated evidence commit could not be checked out'
  [[ "$(git_read -C "$destination" rev-parse --verify HEAD^{commit})" == "$expected_commit" \
    && "$(git_read -C "$destination" status --porcelain=v1)" == '' ]] \
    || die 'isolated evidence source is not the exact clean commit'
}

generate_release_evidence() {
  local output_parent output_leaf before_results after_result gate_log gate_status
  local copied_result evidence_file isolated_source expected_result_digest
  local frozen_result_bundle_digest='' generated_evidence_digest='' pre_handoff_source_token
  local parent_identity stage_identity parent_device parent_inode stage_device stage_inode
  abs_dir "$source_dir" source-dir
  abs_dir "$output_dir" output-dir
  oid "$commit" commit
  reject_production_overrides
  [[ ! -e "$output_dir" && ! -L "$output_dir" ]] \
    || die 'evidence output directory must not already exist'
  [[ "$(git_read -C "$source_dir" rev-parse --show-toplevel)" == "$source_dir" ]] \
    || die 'source-dir is not the worktree root'
  [[ "$(git_read -C "$source_dir" rev-parse --verify HEAD^{commit})" == "$commit" ]] \
    || die 'source HEAD is not the evidence commit'
  [[ "$(git_read -C "$source_dir" status --porcelain=v1)" == '' ]] \
    || die 'source tree must be clean before evidence generation'
  regular "$source_dir/scripts/prepublish-check.sh" prepublication-gate
  [[ -x "$source_dir/scripts/prepublish-check.sh" ]] \
    || die 'prepublication gate is not executable'
  output_parent="$(/usr/bin/dirname -- "$output_dir")"
  output_leaf="${output_dir##*/}"
  [[ -n "$output_leaf" && -d "$output_parent" && ! -L "$output_parent" ]] \
    || die 'evidence output parent is invalid'
  evidence_parent_physical="$(cd -- "$output_parent" && /bin/pwd -P)" \
    || die 'evidence output parent could not be resolved'
  output_dir="$evidence_parent_physical/$output_leaf"
  [[ ! -e "$output_dir" && ! -L "$output_dir" ]] \
    || die 'resolved evidence output directory must not already exist'
  evidence_stage="$(/usr/bin/mktemp -d "$evidence_parent_physical/.lectureboard-v1-evidence.XXXXXX")" \
    || die 'evidence staging directory could not be created'
  parent_identity="$(directory_identity "$evidence_parent_physical")" \
    || die 'evidence output-parent identity could not be captured'
  stage_identity="$(directory_identity "$evidence_stage")" \
    || die 'evidence staging-directory identity could not be captured'
  parent_device="${parent_identity% *}"; parent_inode="${parent_identity#* }"
  stage_device="${stage_identity% *}"; stage_inode="${stage_identity#* }"
  temp="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-evidence-run.XXXXXX)" \
    || die 'evidence run directory could not be created'
  isolated_source="$temp/source"
  create_isolated_commit_source "$source_dir" "$commit" "$isolated_source"
  before_results="$temp/before-results.json"
  /usr/bin/python3 -I - "$isolated_source/DerivedData/AppTests/Logs/Test" "$before_results" <<'PY'
import json,os,sys
root,out=sys.argv[1:]
names=[]
if os.path.isdir(root):
 names=sorted(name for name in os.listdir(root)
              if name.startswith("Test-LectureBoardAI-") and name.endswith(".xcresult")
              and os.path.isdir(os.path.join(root,name)) and not os.path.islink(os.path.join(root,name)))
with open(out,"x",encoding="utf-8") as stream: json.dump(names,stream)
PY
  gate_log="$temp/prepublication-gate.log"
  /usr/bin/printf 'LectureBoard evidence transaction source commit: %s\n' \
    "$commit" >"$gate_log"
  set +e
  (cd -- "$isolated_source" && ./scripts/prepublish-check.sh) 2>&1 \
    | /usr/bin/tee -a "$gate_log"
  gate_status="${PIPESTATUS[0]}"
  set -e
  [[ "$gate_status" == 0 ]] || die 'prepublication gate did not pass'
  [[ "$(git_read -C "$isolated_source" rev-parse --verify HEAD^{commit})" == "$commit" \
    && "$(git_read -C "$isolated_source" status --porcelain=v1)" == '' ]] \
    || die 'isolated source commit or clean state changed during evidence generation'
  /usr/bin/printf 'LectureBoard evidence transaction completed for source commit: %s\n' \
    "$commit" >>"$gate_log"
  after_result="$({ /usr/bin/python3 -I - \
    "$isolated_source/DerivedData/AppTests/Logs/Test" "$before_results" <<'PY'
import json,os,re,sys
root,before_path=sys.argv[1:]
before=set(json.load(open(before_path,encoding="utf-8")))
after=[]
if os.path.isdir(root):
 for name in os.listdir(root):
  path=os.path.join(root,name)
  if name not in before and re.fullmatch(r"Test-LectureBoardAI-[0-9._+-]+\.xcresult",name) and os.path.isdir(path) and not os.path.islink(path):
   after.append(path)
if len(after)!=1: raise SystemExit(1)
print(after[0])
PY
  } )" || die 'exactly one new authoritative native result bundle was not produced'
  copied_result="$evidence_stage/${after_result##*/}"
  freeze_result_bundle_when_stable "$after_result" "$copied_result" "$isolated_source" \
    || die 'authoritative result bundle did not become stable and freeze consistently'
  /bin/cp -X "$gate_log" "$evidence_stage/prepublication-gate.log" \
    || die 'prepublication gate log could not be frozen'
  evidence_file="$evidence_stage/$release_test_evidence_name"
  write_release_test_evidence "$evidence_file" "$commit" \
    "$evidence_stage/prepublication-gate.log" "$copied_result" "$isolated_source" \
    "$frozen_result_bundle_digest"
  regular_file_matches_sha256 "$evidence_file" "$generated_evidence_digest" \
    || die 'generated evidence changed after validation'
  expected_result_digest="$(/usr/bin/plutil -extract nativeAppTests.resultBundleTreeSha256 \
    raw -o - "$evidence_file" 2>/dev/null)" \
    || die 'generated evidence result-bundle digest is unavailable'
  [[ "$expected_result_digest" == "$frozen_result_bundle_digest" ]] \
    || die 'generated evidence does not bind the frozen result-bundle digest'
  /usr/bin/clang -std=c17 -Wall -Wextra -Werror -O2 \
    "$isolated_source/scripts/release-exclusive-rename.c" \
    -o "$temp/release-exclusive-rename" \
    || die 'exclusive evidence handoff helper could not be compiled'
  private_evidence_directory_is_exact "$evidence_stage" "${after_result##*/}" \
    || die 'private evidence directory does not contain exactly the required three entries'
  regular_file_matches_sha256 "$evidence_file" "$generated_evidence_digest" \
    || die 'evidence JSON changed before exclusive handoff'
  release_test_evidence_is_valid "$evidence_file" "$commit" \
    || die 'evidence JSON became invalid before exclusive handoff'
  release_gate_log_matches "$evidence_file" "$evidence_stage/prepublication-gate.log" \
    || die 'evidence changed before exclusive handoff'
  release_gate_script_matches_commit "$evidence_file" "$isolated_source" "$commit" \
    || die 'evidence gate-script binding changed before exclusive handoff'
  pre_handoff_source_token="$(result_bundle_stability_token "$after_result")" \
    || die 'source result-bundle stability could not be verified before exclusive handoff'
  result_bundle_pair_matches_digest "$after_result" "$copied_result" \
    "$isolated_source" "$expected_result_digest" "$pre_handoff_source_token" \
    || die 'source or frozen result bundle changed before exclusive handoff'
  published_evidence_parent="$evidence_parent_physical"
  published_evidence_parent_identity="$parent_identity"
  published_evidence_stage="$evidence_stage"
  published_evidence_dir="$output_dir"
  published_evidence_identity="$stage_identity"
  published_evidence_parent_fd=''
  published_evidence_stage_fd=''
  if ! exec 9<"$published_evidence_parent"; then
    die 'evidence output-parent descriptor could not be retained for handoff'
  fi
  if ! exec 8<"$published_evidence_stage"; then
    exec 9<&-
    die 'evidence staging descriptor could not be retained for handoff'
  fi
  published_evidence_parent_fd=9
  published_evidence_stage_fd=8
  directory_descriptor_matches_identity \
    "$published_evidence_parent_fd" "$published_evidence_parent_identity" \
    || die 'retained evidence output-parent descriptor has the wrong identity'
  directory_descriptor_matches_identity \
    "$published_evidence_stage_fd" "$published_evidence_identity" \
    || die 'retained evidence staging descriptor has the wrong identity'
  "$temp/release-exclusive-rename" "$evidence_stage" "$output_dir" \
    "$parent_device" "$parent_inode" "$stage_device" "$stage_inode" \
    || die 'completed evidence directory could not be published exclusively'
  evidence_stage=''
  validate_published_evidence_handoff \
    "$published_evidence_parent" "$published_evidence_parent_identity" \
    "$published_evidence_stage" "$published_evidence_dir" "$published_evidence_identity" \
    "$published_evidence_parent_fd" "$published_evidence_stage_fd" \
    "${after_result##*/}" "$generated_evidence_digest" "$isolated_source" "$commit" \
    || die 'published evidence changed or failed validation during handoff'
  exec 8<&-
  exec 9<&-
  published_evidence_parent_fd=''
  published_evidence_stage_fd=''
  published_evidence_parent=''
  published_evidence_parent_identity=''
  published_evidence_stage=''
  published_evidence_dir=''
  published_evidence_identity=''
  /usr/bin/printf 'release evidence generated: %s\n' \
    "$output_dir/$release_test_evidence_name"
  /usr/bin/printf 'authoritative result bundle: %s\n' \
    "$output_dir/${after_result##*/}"
  /usr/bin/printf 'prepublication gate log: %s\n' \
    "$output_dir/prepublication-gate.log"
}

release_test_evidence_tree_digest_matches() {
  local evidence_path="$1" result_bundle="$2" source_root="$3"
  local expected_name expected_digest actual_digest
  expected_name="$(/usr/bin/plutil -extract nativeAppTests.resultBundleName raw -o - "$evidence_path" 2>/dev/null)" \
    || return 1
  expected_digest="$(/usr/bin/plutil -extract nativeAppTests.resultBundleTreeSha256 raw -o - "$evidence_path" 2>/dev/null)" \
    || return 1
  [[ "${result_bundle##*/}" == "$expected_name" ]] || return 1
  actual_digest="$(result_bundle_tree_digest "$result_bundle" "$source_root")" || return 1
  [[ "$actual_digest" == "$expected_digest" ]]
}

release_test_evidence_matches_result_bundle() {
  local evidence_path="$1" result_bundle="$2" source_root="$3"
  local summary_root summary_path build_path action_path expected_digest expected_commit
  local macos_version macos_build xcode_version xcode_build status=0
  [[ "$result_bundle" == /* && -d "$result_bundle" && ! -L "$result_bundle" ]] || return 1
  expected_digest="$(/usr/bin/plutil -extract nativeAppTests.resultBundleTreeSha256 raw -o - "$evidence_path" 2>/dev/null)" \
    || return 1
  summary_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-result-bundle-summary.XXXXXX)" \
    || return 1
  summary_path="$summary_root/result-bundle-summary.json"
  build_path="$summary_root/result-bundle-build.json"
  action_path="$summary_root/result-bundle-action.json"
  expected_commit="$(/usr/bin/plutil -extract sourceCommit raw -o - "$evidence_path" 2>/dev/null)" \
    || return 1
  if ! extract_result_bundle_query_outputs "$result_bundle" "$source_root" "$expected_digest" \
    "$summary_path" "$build_path" "$action_path"; then
    status=1
  elif ! macos_version="$(/usr/bin/sw_vers -productVersion)" \
    || ! macos_build="$(/usr/bin/sw_vers -buildVersion)" \
    || ! xcode_version="$(/usr/bin/xcodebuild -version | /usr/bin/awk 'NR == 1 { print $2 }')" \
    || ! xcode_build="$(/usr/bin/xcodebuild -version | /usr/bin/awk 'NR == 2 { print $3 }')"; then
    status=1
  elif ! native_result_summary_is_valid "$evidence_path" "$summary_path" "$build_path" \
    "$action_path" "$expected_commit" "$macos_version" "$macos_build" \
    "$xcode_version" "$xcode_build"; then
    status=1
  fi
  /usr/bin/find "$summary_root" -depth -delete || status=1
  [[ "$status" == 0 ]] || return 1
  return 0
}

checksum_manifest_is_exact() {
  local checksum_path="$1"
  [[ "$(/usr/bin/awk 'END {print NR}' "$checksum_path")" == 4 \
    && "$(/usr/bin/awk 'NF == 2 && length($1) == 64 && $1 ~ /^[0-9a-f]+$/ { print $2 }' "$checksum_path")" == "$release_payload_name_list" ]]
}

release_directory_has_exact_assets() {
  local directory="$1" names count
  [[ "$directory" == /* && -d "$directory" && ! -L "$directory" ]] || return 1
  names="$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 -type f -exec /usr/bin/basename {} \; | /usr/bin/sort)" \
    || return 1
  count="$(/usr/bin/find "$directory" -mindepth 1 -maxdepth 1 | /usr/bin/wc -l | /usr/bin/tr -d ' ')" \
    || return 1
  [[ "$names" == "$release_asset_name_list" && "$count" == 5 ]]
}

release_asset_sizes_are_bounded() {
  local directory="$1"
  bounded_regular "$directory/LectureBoard-AI-v1.0.0-arm64.zip" archive 536870912
  bounded_regular "$directory/$release_test_evidence_name" test-result 32768
  bounded_regular "$directory/SBOM.spdx.json" SBOM 1048576
  bounded_regular "$directory/SHA256SUMS" checksum 4096
  bounded_regular "$directory/provenance.json" provenance 1048576
}

public_inputs_match_snapshot() {
  local acquired_assets="$1" snapshot_assets="$2"
  local acquired_metadata="$3" snapshot_metadata="$4"
  local acquired_refs="$5" snapshot_refs="$6" name
  release_directory_has_exact_assets "$acquired_assets" || return 1
  release_directory_has_exact_assets "$snapshot_assets" || return 1
  [[ "$acquired_metadata" == /* && -f "$acquired_metadata" \
    && ! -L "$acquired_metadata" && "$snapshot_metadata" == /* \
    && -f "$snapshot_metadata" && ! -L "$snapshot_metadata" \
    && "$acquired_refs" == /* && -f "$acquired_refs" \
    && ! -L "$acquired_refs" && "$snapshot_refs" == /* \
    && -f "$snapshot_refs" && ! -L "$snapshot_refs" ]] || return 1
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$(/usr/bin/stat -f '%d:%i' "$acquired_assets/$name")" \
      != "$(/usr/bin/stat -f '%d:%i' "$snapshot_assets/$name")" ]] \
      || return 1
    /usr/bin/cmp -s -- "$acquired_assets/$name" "$snapshot_assets/$name" \
      || return 1
  done <<<"$release_asset_name_list"
  [[ "$(/usr/bin/stat -f '%d:%i' "$acquired_metadata")" \
    != "$(/usr/bin/stat -f '%d:%i' "$snapshot_metadata")" \
    && "$(/usr/bin/stat -f '%d:%i' "$acquired_refs")" \
    != "$(/usr/bin/stat -f '%d:%i' "$snapshot_refs")" ]] || return 1
  /usr/bin/cmp -s -- "$acquired_metadata" "$snapshot_metadata" \
    && /usr/bin/cmp -s -- "$acquired_refs" "$snapshot_refs"
}

public_release_metadata_is_valid() {
  local metadata="$1" expected_commit="$2" approved="$3" downloaded="$4"
  regular "$metadata" public-release-metadata
  /usr/bin/python3 -I - "$metadata" "$expected_commit" "$approved" "$downloaded" <<'PY'
import hashlib,json,os,re,sys,urllib.parse
metadata,commit,approved,downloaded=sys.argv[1:]
def reject_duplicates(pairs):
 out={}
 for key,value in pairs:
  if key in out: raise ValueError("duplicate JSON key")
  out[key]=value
 return out
try:
 if os.path.getsize(metadata)>4*1024*1024: raise ValueError("oversized metadata")
 with open(metadata,encoding="utf-8") as stream:
  release=json.load(stream,object_pairs_hook=reject_duplicates)
except Exception:
 raise SystemExit(1)
names=["LectureBoard-AI-v1.0.0-arm64.zip","LectureBoard-AI-v1.0.0-test-results.json","SBOM.spdx.json","SHA256SUMS","provenance.json"]
if not isinstance(release,dict) or release.get("tag_name")!="v1.0.0" or release.get("name")!="LectureBoard AI v1.0.0":
 raise SystemExit(1)
target=release.get("target_commitish")
if not isinstance(target,str) or not re.fullmatch(r"[0-9A-Za-z._/-]{1,255}",target) or target.startswith("/") or ".." in target:
 raise SystemExit(1)
if release.get("draft") is not False or release.get("prerelease") is not False or release.get("immutable") is not True or not isinstance(release.get("published_at"),str):
 raise SystemExit(1)
try:
 import datetime
 datetime.datetime.strptime(release["published_at"],"%Y-%m-%dT%H:%M:%SZ")
except ValueError:
 raise SystemExit(1)
if release.get("html_url")!="https://github.com/akiyama709/lectureboard-ai/releases/tag/v1.0.0":
 raise SystemExit(1)
if type(release.get("id")) is not int or release["id"]<1:
 raise SystemExit(1)
assets=release.get("assets")
if not isinstance(assets,list) or len(assets)!=len(names): raise SystemExit(1)
by_name={}
for asset in assets:
 if not isinstance(asset,dict) or not isinstance(asset.get("name"),str) or asset["name"] in by_name:
  raise SystemExit(1)
 by_name[asset["name"]]=asset
if sorted(by_name)!=sorted(names): raise SystemExit(1)
for name in names:
 asset=by_name[name]
 approved_path=os.path.join(approved,name); downloaded_path=os.path.join(downloaded,name)
 if asset.get("state")!="uploaded" or type(asset.get("size")) is not int:
  raise SystemExit(1)
 if asset["size"]!=os.path.getsize(approved_path) or asset["size"]!=os.path.getsize(downloaded_path):
  raise SystemExit(1)
 expected_url="https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/"+urllib.parse.quote(name,safe="")
 if asset.get("browser_download_url")!=expected_url: raise SystemExit(1)
 digest=asset.get("digest")
 if digest is not None:
  hasher=hashlib.sha256()
  with open(downloaded_path,"rb") as stream:
   for chunk in iter(lambda:stream.read(1024*1024),b""): hasher.update(chunk)
  actual="sha256:"+hasher.hexdigest()
  if digest!=actual: raise SystemExit(1)
PY
}

public_tag_refs_are_valid() {
  local refs_path="$1" expected_commit="$2" expected_tag_object="$3"
  regular "$refs_path" public-tag-refs
  /usr/bin/python3 -I - "$refs_path" "$expected_commit" "$expected_tag_object" <<'PY'
import os,re,sys
path,commit,tag_object=sys.argv[1:]
try:
 if os.path.getsize(path)>4096: raise ValueError("oversized refs")
 lines=open(path,encoding="ascii",errors="strict").read().splitlines()
except Exception:
 raise SystemExit(1)
if len(lines)!=2: raise SystemExit(1)
parsed={}
for line in lines:
 match=re.fullmatch(r"([0-9a-f]{40}|[0-9a-f]{64})\t(refs/tags/v1\.0\.0(?:\^\{\})?)",line)
 if not match or match.group(2) in parsed: raise SystemExit(1)
 parsed[match.group(2)]=match.group(1)
if parsed!={"refs/tags/v1.0.0":tag_object,"refs/tags/v1.0.0^{}":commit} or tag_object==commit:
 raise SystemExit(1)
PY
}

release_sbom_is_valid() {
  local sbom_path="$1" expected_commit="$2" expected_archive_sha="$3"
  /usr/bin/python3 -I - "$sbom_path" "$expected_commit" "$expected_archive_sha" <<'PY'
import datetime,json,os,re,sys
path,commit,archive_sha=sys.argv[1:]
def reject_duplicates(pairs):
 out={}
 for key,value in pairs:
  if key in out: raise ValueError("duplicate JSON key")
  out[key]=value
 return out
def exact(value,keys): return isinstance(value,dict) and set(value)==set(keys)
try:
 if os.path.getsize(path)>1024*1024: raise ValueError("oversized SBOM")
 with open(path,encoding="utf-8") as stream: data=json.load(stream,object_pairs_hook=reject_duplicates)
except Exception:
 raise SystemExit(1)
top={"spdxVersion","dataLicense","SPDXID","name","documentNamespace","creationInfo","packages","documentDescribes"}
if not exact(data,top): raise SystemExit(1)
if (data["spdxVersion"],data["dataLicense"],data["SPDXID"],data["name"])!=("SPDX-2.3","CC0-1.0","SPDXRef-DOCUMENT","LectureBoard AI v1.0.0"): raise SystemExit(1)
if data["documentNamespace"]!="https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/SBOM.spdx.json#"+commit: raise SystemExit(1)
creation=data["creationInfo"]
if not exact(creation,{"created","creators"}) or creation["creators"]!=["Tool: no-fee-release-v1.sh"]: raise SystemExit(1)
try: datetime.datetime.strptime(creation["created"],"%Y-%m-%dT%H:%M:%SZ")
except (TypeError,ValueError): raise SystemExit(1)
if data["documentDescribes"]!=["SPDXRef-Package-LectureBoardAI"] or not isinstance(data["packages"],list) or len(data["packages"])!=1: raise SystemExit(1)
package=data["packages"][0]
package_keys={"SPDXID","name","versionInfo","downloadLocation","supplier","filesAnalyzed","checksums","licenseConcluded","licenseDeclared","copyrightText"}
if not exact(package,package_keys): raise SystemExit(1)
expected={"SPDXID":"SPDXRef-Package-LectureBoardAI","name":"LectureBoard AI","versionInfo":"1.0.0","downloadLocation":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/LectureBoard-AI-v1.0.0-arm64.zip","supplier":"Person: Tomohiro Akiyama","filesAnalyzed":False,"licenseConcluded":"MIT","licenseDeclared":"MIT","copyrightText":"Copyright (c) 2026 Tomohiro Akiyama"}
for key,value in expected.items():
 if package.get(key)!=value or type(package.get(key)) is not type(value): raise SystemExit(1)
checksums=package["checksums"]
if not isinstance(checksums,list) or len(checksums)!=1 or not exact(checksums[0],{"algorithm","checksumValue"}): raise SystemExit(1)
if checksums[0]!={"algorithm":"SHA256","checksumValue":archive_sha}: raise SystemExit(1)
PY
}

release_provenance_is_valid() {
  local provenance_path="$1" expected_commit="$2" expected_archive_sha="$3" expected_test_sha="$4"
  /usr/bin/python3 -I - "$provenance_path" "$expected_commit" "$expected_archive_sha" "$expected_test_sha" <<'PY'
import json,os,re,sys
path,commit,archive_sha,test_sha=sys.argv[1:]
def reject_duplicates(pairs):
 out={}
 for key,value in pairs:
  if key in out: raise ValueError("duplicate JSON key")
  out[key]=value
 return out
def exact(value,keys): return isinstance(value,dict) and set(value)==set(keys)
try:
 if os.path.getsize(path)>1024*1024: raise ValueError("oversized provenance")
 with open(path,encoding="utf-8") as stream: data=json.load(stream,object_pairs_hook=reject_duplicates)
except Exception:
 raise SystemExit(1)
keys={"schema","repository","tag","tagObject","commit","bundleIdentifier","version","architecture","configuration","signature","hardenedRuntime","entitlements","toolchain","archive","executableSha256","testResult"}
if not exact(data,keys): raise SystemExit(1)
expected={"schema":"lectureboard.no-fee-provenance.v1","repository":"akiyama709/lectureboard-ai","tag":"v1.0.0","commit":commit,"bundleIdentifier":"io.github.akiyama709.LectureBoardAI","version":"1.0.0","architecture":"arm64","configuration":"Release","signature":"ad hoc","hardenedRuntime":True}
for key,value in expected.items():
 if data.get(key)!=value or type(data.get(key)) is not type(value): raise SystemExit(1)
if not isinstance(data["tagObject"],str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",data["tagObject"]): raise SystemExit(1)
if not isinstance(data["executableSha256"],str) or not re.fullmatch(r"[0-9a-f]{64}",data["executableSha256"]): raise SystemExit(1)
if not isinstance(data["toolchain"],str) or not re.fullmatch(r"Xcode [0-9]+(?:\.[0-9]+){1,2}; Build version [0-9A-Za-z]+",data["toolchain"]): raise SystemExit(1)
entitlements=data["entitlements"]
if not exact(entitlements,{"keys","canonicalJsonSha256"}) or entitlements!={"keys":["com.apple.security.automation.apple-events","com.apple.security.device.audio-input"],"canonicalJsonSha256":"2ef41daa1f5a828d3492e8e40efdd881b539169e6b1b95aad9be949c73de01b0"}: raise SystemExit(1)
if not exact(data["archive"],{"name","sha256"}) or data["archive"]!={"name":"LectureBoard-AI-v1.0.0-arm64.zip","sha256":archive_sha}: raise SystemExit(1)
if not exact(data["testResult"],{"name","sha256"}) or data["testResult"]!={"name":"LectureBoard-AI-v1.0.0-test-results.json","sha256":test_sha}: raise SystemExit(1)
PY
}

toolchain_identity() {
  /usr/bin/xcodebuild -version | /usr/bin/awk '
    NR == 1 { first = $0 }
    NR == 2 { print first "; " $0; found = 1 }
    END { if (!found) exit 1 }
  '
}
toolchain_value_is_valid() {
  [[ "$1" =~ ^Xcode\ [0-9]+(\.[0-9]+){1,2}\;\ Build\ version\ [0-9A-Za-z]+$ ]]
}

application_content_has_no_private_paths() {
  local app_path="$1"
  [[ "$app_path" == /* && -d "$app_path" && ! -L "$app_path" ]] || return 1
  /usr/bin/python3 -I - "$app_path" <<'PY'
import os,re,stat,sys,unicodedata
root=sys.argv[1]
pattern=re.compile(r"(/Users/|/private/tmp/|/var/folders/|/Volumes/|\.pptx?(?:[^0-9A-Za-z]|$)|\.keynote(?:[^0-9A-Za-z]|$))",re.I)
total=0
def walk_error(error): raise error
for base,dirs,files in os.walk(root,followlinks=False,onerror=walk_error):
 dirs.sort(); files.sort()
 for name in dirs+files:
  path=os.path.join(base,name)
  mode=os.lstat(path).st_mode
  relative=unicodedata.normalize("NFKC",os.path.relpath(path,root))
  if os.path.islink(path) or pattern.search(relative): raise SystemExit(1)
  if stat.S_ISDIR(mode) and mode&0o500!=0o500: raise SystemExit(1)
  if stat.S_ISREG(mode) and mode&0o400!=0o400: raise SystemExit(1)
 for name in files:
  path=os.path.join(base,name)
  try:
   size=os.path.getsize(path); total+=size
   if size>256*1024*1024 or total>512*1024*1024: raise ValueError("oversized application")
   raw=open(path,"rb").read()
  except Exception: raise SystemExit(1)
  texts=[raw.decode("utf-8",errors="ignore")]
  for offset in (0,1):
   for encoding in ("utf-16-le","utf-16-be"):
    try: texts.append(raw[offset:].decode(encoding,errors="ignore"))
    except Exception: pass
  if any(pattern.search(unicodedata.normalize("NFKC",text)) for text in texts):
   raise SystemExit(1)
PY
}

signed_component_has_no_entitlements() {
  local component="$1" entitlement_file status=0
  entitlement_file="$(/usr/bin/mktemp /private/tmp/lectureboard-nested-entitlements.XXXXXX)" \
    || return 1
  if ! /usr/bin/codesign -d --entitlements :- "$component" \
    >"$entitlement_file" 2>/dev/null; then
    status=1
  elif [[ -s "$entitlement_file" ]] \
    && ! /usr/bin/plutil -convert json -o - "$entitlement_file" \
      | /usr/bin/python3 -I -c 'import json,sys
if json.load(sys.stdin) != {}: raise SystemExit(1)' >/dev/null; then
    status=1
  fi
  /bin/unlink "$entitlement_file" || status=1
  [[ "$status" == 0 ]]
}

# The receipt is a read-only, adjacent manifest emitted only after the isolated
# approved-commit build has itself passed the full app verification boundary.
app_manifest_sha() {
  /usr/bin/python3 -I -c 'import hashlib,os,stat,sys
r=sys.argv[1]; rows=[]
for b,ds,fs in os.walk(r,followlinks=False):
 ds.sort();fs.sort()
 for n in ds+fs:
  m=os.lstat(os.path.join(b,n)).st_mode
  if stat.S_ISLNK(m) or not (stat.S_ISREG(m) or stat.S_ISDIR(m)): raise SystemExit(1)
 for n in fs:
  p=os.path.join(b,n); q=os.path.relpath(p,r)
  if q.startswith("../") or "\\x00" in q: raise SystemExit(1)
  rows.append(q+"\\t%04o\\t"%stat.S_IMODE(os.lstat(p).st_mode)+hashlib.sha256(open(p,"rb").read()).hexdigest()+"\\n")
print(hashlib.sha256("".join(rows).encode()).hexdigest())' "$1" || die 'application manifest calculation failed'
}
write_build_receipt() {
  local out="$1" app="$2" toolchain="$3" manifest
  toolchain_value_is_valid "$toolchain" || die 'build toolchain identity is malformed'
  manifest="$(app_manifest_sha "$app")"
  /usr/bin/python3 -I - "$out" "$commit" "$tag_expected" "$manifest" "$toolchain" <<'PY'
import json,sys
p,c,t,m,x=sys.argv[1:]
json.dump({"schema":"lectureboard.approved-isolated-build-receipt.v1","commit":c,"tag":t,"appRelativePath":"LectureBoard AI.app","appManifestSha256":m,"toolchain":x,"buildIsolation":"git-archive-approved-commit"},open(p,"w"),sort_keys=True,separators=(",",":"));open(p,"a").write("\n")
PY
  /bin/chmod 444 "$out" || die 'build receipt protection failed'
}
verify_build_receipt() {
  local receipt="$1" app="$2" m
  regular "$receipt" build-receipt
  [[ "${receipt##*/}" == approved-build-receipt.json && "$(/usr/bin/dirname -- "$app")/approved-build-receipt.json" == "$receipt" && ! -w "$receipt" ]] || die 'build receipt placement or protection invalid'
  m="$(app_manifest_sha "$app")"
  /usr/bin/python3 -I - "$receipt" "$commit" "$tag_expected" "$m" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert set(d)=={"schema","commit","tag","appRelativePath","appManifestSha256","toolchain","buildIsolation"}
assert d["schema"]=="lectureboard.approved-isolated-build-receipt.v1" and d["commit"]==sys.argv[2] and d["tag"]==sys.argv[3] and d["appRelativePath"]=="LectureBoard AI.app" and d["appManifestSha256"]==sys.argv[4] and d["buildIsolation"]=="git-archive-approved-commit"
import re
assert isinstance(d["toolchain"],str) and re.fullmatch(r"Xcode [0-9]+(?:\.[0-9]+){1,2}; Build version [0-9A-Za-z]+",d["toolchain"])
PY
  [[ $? == 0 ]] || die 'build receipt does not bind the handed-off application'
}

reject_production_overrides() {
  local n
  for n in BASH_ENV ENV GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
    GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 XCODE_XCCONFIG_FILE DEVELOPER_DIR SDKROOT \
    TOOLCHAINS SWIFT_EXEC CC CXX LD DYLD_LIBRARY_PATH DYLD_INSERT_LIBRARIES CODESIGN_ALLOCATE \
    TAR_OPTIONS ZIPOPT UNZIP UNZIPOPT PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONUSERBASE \
    PYTHONINSPECT PERL5OPT PERL5LIB RUBYOPT; do
    [[ -z "${!n:-}" ]] || die "production input cannot set $n"
  done
}

git_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0)
git_read() {
  "${git_env[@]}" /usr/bin/git --no-replace-objects \
    -c core.hooksPath=/dev/null -c core.attributesFile=/dev/null \
    -c core.fsmonitor=false -c core.untrackedCache=false "$@"
}

repository_file_matches_commit() {
  local source_root="$1" expected_commit="$2" relative_path="$3" actual_blob expected_blob
  [[ "$relative_path" != /* && "$relative_path" != *'..'* \
    && -f "$source_root/$relative_path" && ! -L "$source_root/$relative_path" ]] \
    || return 1
  actual_blob="$(git_read -C "$source_root" hash-object --no-filters -- \
    "$source_root/$relative_path")" \
    || return 1
  expected_blob="$(git_read -C "$source_root" rev-parse \
    "$expected_commit:$relative_path")" || return 1
  [[ "$actual_blob" == "$expected_blob" ]]
}

release_tool_matches_commit() {
  local source_root="$1" expected_commit="$2" tool_path
  tool_path="$(cd -- "$(/usr/bin/dirname -- "$0")" && /bin/pwd -P)/$(/usr/bin/basename -- "$0")" \
    || return 1
  [[ "$tool_path" == "$source_root/scripts/no-fee-release-v1.sh" ]] || return 1
  repository_file_matches_commit \
    "$source_root" "$expected_commit" scripts/no-fee-release-v1.sh
}

commit_contains_git_attributes() {
  local repository="$1" expected_commit="$2"
  git_read -C "$repository" ls-tree -r -z --name-only "$expected_commit" \
    | /usr/bin/python3 -I -c 'import posixpath,sys
paths=sys.stdin.buffer.read().split(b"\0")
raise SystemExit(0 if any(posixpath.basename(path)==b".gitattributes" for path in paths if path) else 1)'
}

parse_args() {
  command="$1"; shift
  while (( $# )); do
    case "$1" in
      --source-dir|--output-dir|--approved-dir|--downloaded-dir|--app|--build-receipt|--archive|--commit|--tag|--test-result|--test-result-bundle|--gate-log|--checksum|--sbom|--provenance|--release-metadata|--tag-refs)
        (( $# >= 2 )) || { usage >&2; exit 64; }
        case "$1" in
          --source-dir) key=source_dir;; --output-dir) key=output_dir;; --test-result) key=test_result;;
          --test-result-bundle) key=test_result_bundle;; --build-receipt) key=build_receipt;;
          --gate-log) key=gate_log;; --release-metadata) key=release_metadata;; --tag-refs) key=tag_refs;;
          --approved-dir) key=approved_dir;; --downloaded-dir) key=downloaded_dir;;
          --provenance) key=provenance;; *) key="${1#--}";;
        esac
        [[ -z "${!key+x}" ]] || die "duplicate --$key"; printf -v "$key" '%s' "$2"; shift 2;;
      --help) usage; exit 0;; *) usage >&2; exit 64;;
    esac
  done
}

verify_app() {
  local app="$1" expected_commit="$2" expected_tag_object="$3" info exe ent keys details components nested_details
  [[ "$app" == /* && -d "$app" && ! -L "$app" && "${app##*/}" == "$product.app" ]] || die 'application bundle path/name is invalid'
  info="$app/Contents/Info.plist"; exe="$app/Contents/MacOS/$product"
  regular "$info" 'application Info.plist'; [[ -x "$exe" && ! -L "$exe" ]] || die 'application executable is missing'
  application_content_has_no_private_paths "$app" \
    || die 'application contains a private path or lecture-file reference'
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null)" == "$bundle_id" ]] || die 'bundle identifier is not exact'
  [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info" 2>/dev/null)" == "$version" ]] || die 'marketing version is not exact'
  [[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info" 2>/dev/null)" =~ ^[1-9][0-9]*$ ]] || die 'build number is invalid'
  [[ "$(/usr/bin/plutil -extract LectureBoardReleaseCommit raw -o - "$info" 2>/dev/null)" == "$expected_commit" ]] || die 'bundle commit provenance is not exact'
  [[ "$(/usr/bin/plutil -extract LectureBoardReleaseTag raw -o - "$info" 2>/dev/null)" == "$tag_expected" ]] || die 'bundle tag provenance is not exact'
  [[ "$(/usr/bin/plutil -extract LectureBoardReleaseTagObject raw -o - "$info" 2>/dev/null)" == "$expected_tag_object" ]] || die 'bundle tag-object provenance is not exact'
  [[ -z "$(/usr/bin/find "$app/Contents/MacOS" -maxdepth 1 -type f \( -name '*.debug.dylib' -o -name '__preview.dylib' \) -print 2>/dev/null)" ]] || die 'debug dylib is present'
  {
    details="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)" || die 'codesign inspection failed'
    [[ "$details" == *'Signature=adhoc'* && "$details" == *'TeamIdentifier=not set'* ]] || die 'application is not ad hoc-only signed'
    [[ "$details" != *'Authority=Developer ID'* && "$details" != *'Authority=Apple Development'* && "$details" != *'Timestamp='* ]] || die 'Developer ID, development, or timestamp signature rejected'
    hardened_runtime_flag_is_set "$details" || die 'hardened runtime flag is missing'
    [[ "$(/usr/bin/lipo -archs "$exe" 2>/dev/null)" == 'arm64' ]] || die 'application is not thin exact arm64'
    ent="$(/usr/bin/mktemp /private/tmp/lectureboard-entitlements.XXXXXX)" || die 'entitlement staging failed'
    if ! /usr/bin/codesign -d --entitlements :- "$app" >"$ent" 2>/dev/null; then /bin/unlink "$ent"; die 'entitlement inspection failed'; fi
    if ! /usr/bin/plutil -convert json -o - "$ent" | /usr/bin/python3 -I -c 'import json,sys
d=json.load(sys.stdin)
expected={"com.apple.security.automation.apple-events": True,"com.apple.security.device.audio-input": True}
if d != expected: raise SystemExit(1)' >/dev/null; then
      /bin/unlink "$ent"; die 'entitlements are not the exact release allowlist'
    fi
    /bin/unlink "$ent"
    /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || die 'application signature strict verification failed'
    # Libraries are often non-executable files, so inspect every Mach-O object,
    # not merely files whose Unix mode happens to have an execute bit.
    components="$(/usr/bin/find "$app" -type f -print)" || die 'application Mach-O enumeration failed'
    while IFS= read -r component; do
      [[ -n "$component" ]] || continue
      [[ "$component" == "$exe" ]] && continue
      [[ "$(/usr/bin/file "$component")" == *'Mach-O'* ]] || continue
      [[ "$(/usr/bin/lipo -archs "$component" 2>/dev/null)" == 'arm64' ]] || die 'Mach-O is not thin exact arm64'
      /usr/bin/codesign --verify --strict "$component" >/dev/null 2>&1 || die 'nested executable signature verification failed'
      nested_details="$(/usr/bin/codesign -d --verbose=4 "$component" 2>&1)" || die 'nested executable signature inspection failed'
      [[ "$nested_details" == *'Signature=adhoc'* && "$nested_details" == *'TeamIdentifier=not set'* ]] || die 'nested executable is not ad hoc-only signed'
      [[ "$nested_details" != *'Authority=Developer ID'* && "$nested_details" != *'Authority=Apple Development'* && "$nested_details" != *'Timestamp='* ]] || die 'nested Developer ID, development, or timestamp signature rejected'
      hardened_runtime_flag_is_set "$nested_details" || die 'nested executable hardened runtime flag is missing'
      signed_component_has_no_entitlements "$component" \
        || die 'nested executable carries an entitlement'
    done <<< "$components"
  }
}

build_production() {
  local isolated_repository build_toolchain_before build_toolchain_after
  abs_dir "$source_dir" source-dir; abs_dir "$output_dir" output-dir; oid "$commit" commit; [[ "$tag" == "$tag_expected" ]] || die 'tag must be v1.0.0'; [[ ! -e "$output_dir" && ! -L "$output_dir" ]] || die 'output directory must not already exist'; reject_production_overrides
  [[ "$(git_read -C "$source_dir" rev-parse --show-toplevel)" == "$source_dir" ]] || die 'source-dir is not the worktree root'
  [[ "$(git_read -C "$source_dir" status --porcelain=v1)" == '' ]] || die 'source tree is dirty'
  target="$(git_read -C "$source_dir" rev-parse --verify "$tag^{commit}")" || die 'release tag cannot be resolved'; [[ "$target" == "$commit" ]] || die 'tag does not target approved commit'
  tag_object="$(git_read -C "$source_dir" rev-parse --verify "refs/tags/$tag")" || die 'release tag object cannot be resolved'; oid "$tag_object" tag-object
  [[ "$(git_read -C "$source_dir" cat-file -t "refs/tags/$tag")" == tag ]] || die 'release tag must be annotated'
  temp="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-build.XXXXXX)" || die 'temporary build root failed'
  isolated_repository="$temp/repository"
  create_isolated_commit_source \
    "$source_dir" "$commit" "$isolated_repository"
  /bin/mkdir "$temp/source"
  (git_read -C "$isolated_repository" archive --format=tar "$commit" \
    | /usr/bin/tar -xf - -C "$temp/source") \
    || die 'isolated source extraction failed'
  [[ -z "$(/usr/bin/find "$temp/source" -type l -print -quit)" ]] || die 'isolated source contains a symbolic link'
  [[ -z "$(/usr/bin/find "$temp/source" \( -type b -o -type c -o -type p \) -print -quit)" ]] || die 'isolated source contains a special file'
  build_toolchain_before="$(toolchain_identity)" \
    || die 'pre-build toolchain identity could not be read'
  toolchain_value_is_valid "$build_toolchain_before" \
    || die 'pre-build toolchain identity is malformed'
  /usr/bin/xcodebuild -project "$temp/source/LectureBoardAI.xcodeproj" -scheme LectureBoardAI -configuration Release -sdk macosx -arch arm64 -derivedDataPath "$temp/DerivedData" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='' CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=YES ENABLE_DEBUG_DYLIB=NO \
    LECTUREBOARD_RELEASE_COMMIT="$commit" LECTUREBOARD_RELEASE_TAG="$tag" LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" build || die 'isolated Release build failed'
  build_toolchain_after="$(toolchain_identity)" \
    || die 'post-build toolchain identity could not be read'
  [[ "$build_toolchain_after" == "$build_toolchain_before" ]] \
    || die 'toolchain identity changed during the Release build'
  built="$temp/DerivedData/Build/Products/Release/$product.app"; [[ -d "$built" ]] || die 'Release application output missing'; verify_app "$built" "$commit" "$tag_object"
  /bin/mkdir "$output_dir"; /usr/bin/ditto --rsrc --extattr --acl "$built" "$output_dir/$product.app" || die 'verified application handoff failed'; verify_app "$output_dir/$product.app" "$commit" "$tag_object"
  write_build_receipt "$output_dir/approved-build-receipt.json" \
    "$output_dir/$product.app" "$build_toolchain_before"
  verify_build_receipt "$output_dir/approved-build-receipt.json" "$output_dir/$product.app"
}

prepare_release() {
  local final_output_dir="$output_dir" final_parent final_leaf rename_helper
  local parent_identity stage_identity parent_device parent_inode stage_device stage_inode
  regular "$test_result" test-result
  regular "$gate_log" gate-log
  release_test_evidence_is_valid "$test_result" "$commit" \
    || die 'release test evidence is invalid'
  release_gate_log_matches "$test_result" "$gate_log" \
    || die 'release test evidence does not match its prepublication gate log'
  release_gate_script_matches_commit "$test_result" "$source_dir" "$commit" \
    || die 'release test evidence does not match the committed gate script'
  [[ ! -e "$final_output_dir" && ! -L "$final_output_dir" ]] \
    || die 'output directory must not already exist'
  abs_dir "$final_output_dir" output-dir
  final_parent="$(/usr/bin/dirname -- "$final_output_dir")"
  final_leaf="${final_output_dir##*/}"
  [[ -n "$final_leaf" && -d "$final_parent" && ! -L "$final_parent" ]] \
    || die 'release output parent is invalid'
  release_parent_physical="$(cd -- "$final_parent" && /bin/pwd -P)" \
    || die 'release output parent could not be resolved'
  final_output_dir="$release_parent_physical/$final_leaf"
  [[ ! -e "$final_output_dir" && ! -L "$final_output_dir" ]] \
    || die 'resolved output directory must not already exist'
  handoff_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-handoff.XXXXXX)" \
    || die 'temporary handoff root failed'
  output_dir="$handoff_root/approved"
  build_production
  app="$output_dir/$product.app"
  build_receipt="$output_dir/approved-build-receipt.json"
  release_stage="$(/usr/bin/mktemp -d \
    "$release_parent_physical/.lectureboard-v1-release.XXXXXX")" \
    || die 'release staging directory could not be created'
  parent_identity="$(directory_identity "$release_parent_physical")" \
    || die 'release output-parent identity could not be captured'
  stage_identity="$(directory_identity "$release_stage")" \
    || die 'release staging-directory identity could not be captured'
  parent_device="${parent_identity% *}"; parent_inode="${parent_identity#* }"
  stage_device="${stage_identity% *}"; stage_inode="${stage_identity#* }"
  output_dir="$release_stage"
  package_release
  rename_helper="$handoff_root/release-exclusive-rename"
  /usr/bin/clang -std=c17 -Wall -Wextra -Werror -O2 \
    "$temp/source/scripts/release-exclusive-rename.c" -o "$rename_helper" \
    || die 'exclusive release handoff helper could not be compiled'
  "$rename_helper" "$release_stage" "$final_output_dir" \
    "$parent_device" "$parent_inode" "$stage_device" "$stage_inode" \
    || die 'verified release directory could not be published exclusively'
  release_stage=''
  output_dir="$final_output_dir"
}

package_release() {
  local release_test_result archive app_sha archive_sha test_sha toolchain created_at
  local sbom_sha provenance_sha tag_object validated_test_sha validated_gate_log_sha
  abs_dir "$output_dir" output-dir; abs_dir "$source_dir" source-dir; regular "$test_result" test-result; regular "$gate_log" gate-log; oid "$commit" commit; release_test_evidence_is_valid "$test_result" "$commit" || die 'release test evidence is invalid'; [[ "$tag" == "$tag_expected" ]] || die 'tag must be v1.0.0'; [[ -d "$app" ]] || die 'application missing'; [[ -d "$output_dir" && ! -L "$output_dir" && -z "$(/usr/bin/find "$output_dir" -mindepth 1 -print -quit)" ]] || die 'release staging directory is invalid';
  reject_production_overrides
  [[ "$(git_read -C "$source_dir" rev-parse --show-toplevel)" == "$source_dir" ]] || die 'source-dir is not the worktree root'
  [[ "$(git_read -C "$source_dir" status --porcelain=v1)" == '' ]] || die 'source tree is dirty'
  [[ "$(git_read -C "$source_dir" rev-parse --verify HEAD^{commit})" == "$commit" ]] || die 'source HEAD is not the approved commit'
  [[ "$(git_read -C "$source_dir" rev-parse --verify "$tag^{commit}")" == "$commit" ]] || die 'source tag is not bound to the approved commit'
  [[ "$(git_read -C "$source_dir" cat-file -t "refs/tags/$tag")" == tag ]] || die 'release tag must be annotated'
  tag_object="$(git_read -C "$source_dir" rev-parse --verify "refs/tags/$tag")" || die 'source tag object cannot be resolved'; oid "$tag_object" tag-object
  validated_test_sha="$(sha256 "$test_result")"
  validated_gate_log_sha="$(sha256 "$gate_log")"
  release_gate_log_matches "$test_result" "$gate_log" \
    || die 'release test evidence does not match its prepublication gate log'
  release_gate_script_matches_commit "$test_result" "$source_dir" "$commit" \
    || die 'release test evidence does not match the committed gate script'
  release_test_evidence_matches_result_bundle "$test_result" "$test_result_bundle" "$temp/source" \
    || die 'release test evidence does not match the authoritative result bundle and toolchain'
  [[ "$(sha256 "$test_result")" == "$validated_test_sha" ]] \
    || die 'release test evidence changed during validation'
  [[ "$(sha256 "$gate_log")" == "$validated_gate_log_sha" ]] \
    || die 'prepublication gate log changed during validation'
  verify_app "$app" "$commit" "$tag_object"; verify_build_receipt "$build_receipt" "$app"; release_test_result="$output_dir/$release_test_evidence_name"; /bin/cp -X "$test_result" "$release_test_result" || die 'release test evidence copy failed'; /usr/bin/cmp -s "$test_result" "$release_test_result" || die 'release test evidence copy differs'; archive="$output_dir/LectureBoard-AI-v1.0.0-arm64.zip"; create_portable_zip "$app" "$archive";
  app_sha="$(sha256 "$app/Contents/MacOS/$product")"; archive_sha="$(sha256 "$archive")"; test_sha="$(sha256 "$release_test_result")"; [[ "$test_sha" == "$validated_test_sha" ]] || die 'copied release test evidence changed after validation'; json_string "$commit"
  toolchain="$(/usr/bin/plutil -extract toolchain raw -o - "$build_receipt" 2>/dev/null)" \
    || die 'build-receipt toolchain identity could not be read'
  toolchain_value_is_valid "$toolchain" \
    || die 'build-receipt toolchain identity is malformed'
  [[ "$toolchain" == "$(toolchain_identity)" ]] \
    || die 'packaging toolchain differs from the application build toolchain'
  json_string "$toolchain"
  created_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" || die 'SBOM creation time unavailable'; json_string "$created_at"
  /usr/bin/printf '{\n  "spdxVersion":"SPDX-2.3",\n  "dataLicense":"CC0-1.0",\n  "SPDXID":"SPDXRef-DOCUMENT",\n  "name":"LectureBoard AI v1.0.0",\n  "documentNamespace":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/SBOM.spdx.json#%s",\n  "creationInfo":{"created":"%s","creators":["Tool: no-fee-release-v1.sh"]},\n  "packages":[{"SPDXID":"SPDXRef-Package-LectureBoardAI","name":"LectureBoard AI","versionInfo":"1.0.0","downloadLocation":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/%s","supplier":"Person: Tomohiro Akiyama","filesAnalyzed":false,"checksums":[{"algorithm":"SHA256","checksumValue":"%s"}],"licenseConcluded":"MIT","licenseDeclared":"MIT","copyrightText":"Copyright (c) 2026 Tomohiro Akiyama"}],\n  "documentDescribes":["SPDXRef-Package-LectureBoardAI"]\n}\n' "$commit" "$created_at" "${archive##*/}" "$archive_sha" >"$output_dir/SBOM.spdx.json" || die 'SBOM producer failed'
  /usr/bin/printf '{\n  "schema":"lectureboard.no-fee-provenance.v1",\n  "repository":"akiyama709/lectureboard-ai",\n  "tag":"%s",\n  "tagObject":"%s",\n  "commit":"%s",\n  "bundleIdentifier":"%s",\n  "version":"%s",\n  "architecture":"arm64",\n  "configuration":"Release",\n  "signature":"ad hoc",\n  "hardenedRuntime":true,\n  "entitlements":{"keys":["com.apple.security.automation.apple-events","com.apple.security.device.audio-input"],"canonicalJsonSha256":"2ef41daa1f5a828d3492e8e40efdd881b539169e6b1b95aad9be949c73de01b0"},\n  "toolchain":"%s",\n  "archive":{"name":"%s","sha256":"%s"},\n  "executableSha256":"%s",\n  "testResult":{"name":"%s","sha256":"%s"}\n}\n' "$tag" "$tag_object" "$commit" "$bundle_id" "$version" "$toolchain" "${archive##*/}" "$archive_sha" "$app_sha" "$release_test_evidence_name" "$test_sha" >"$output_dir/provenance.json" || die 'provenance producer failed'
  /usr/bin/python3 -I -m json.tool "$output_dir/SBOM.spdx.json" >/dev/null || die 'SBOM is not valid JSON'; /usr/bin/python3 -I -m json.tool "$output_dir/provenance.json" >/dev/null || die 'provenance is not valid JSON';
  sbom_sha="$(sha256 "$output_dir/SBOM.spdx.json")"; provenance_sha="$(sha256 "$output_dir/provenance.json")"
  /usr/bin/printf '%s  %s\n%s  %s\n%s  %s\n%s  %s\n' "$archive_sha" "${archive##*/}" "$test_sha" "$release_test_evidence_name" "$sbom_sha" 'SBOM.spdx.json' "$provenance_sha" 'provenance.json' >"$output_dir/SHA256SUMS" || die 'checksum producer failed'
  release_directory_has_exact_assets "$output_dir" || die 'release asset set is not exact'
  verify_archive "$archive" "$commit" "$output_dir/SHA256SUMS" "$output_dir/SBOM.spdx.json" "$output_dir/provenance.json" "$release_test_result"
}

verify_archive() {
  local archive="$1" expected_commit="$2" checksum="$3" sbom="$4" provenance="$5" expected_test="${6:-}"
  local expected_tag_object ditto_root unzip_root expected_sha expected_test_sha
  local expected_sbom_sha expected_provenance_sha exe_sha
  local original_archive original_checksum original_sbom original_provenance original_test
  reject_production_overrides
  bounded_regular "$archive" archive 536870912
  bounded_regular "$checksum" checksum 4096
  bounded_regular "$sbom" SBOM 1048576
  bounded_regular "$provenance" provenance 1048576
  oid "$expected_commit" commit
  bounded_regular "$expected_test" test-result 32768
  [[ "${archive##*/}" == 'LectureBoard-AI-v1.0.0-arm64.zip' ]] || die 'archive filename is not exact'
  original_archive="$archive"; original_checksum="$checksum"; original_sbom="$sbom"
  original_provenance="$provenance"; original_test="$expected_test"
  verification_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-verify.XXXXXX)" \
    || die 'verification root failed'
  trap '[[ -n "${verification_root:-}" && -d "$verification_root" ]] && /usr/bin/find "$verification_root" -depth -delete' RETURN
  /bin/mkdir "$verification_root/inputs" || die 'verification input snapshot failed'
  /bin/cp -X "$original_archive" "$verification_root/inputs/LectureBoard-AI-v1.0.0-arm64.zip" \
    || die 'archive snapshot failed'
  /bin/cp -X "$original_checksum" "$verification_root/inputs/SHA256SUMS" \
    || die 'checksum snapshot failed'
  /bin/cp -X "$original_sbom" "$verification_root/inputs/SBOM.spdx.json" \
    || die 'SBOM snapshot failed'
  /bin/cp -X "$original_provenance" "$verification_root/inputs/provenance.json" \
    || die 'provenance snapshot failed'
  /bin/cp -X "$original_test" "$verification_root/inputs/$release_test_evidence_name" \
    || die 'test-evidence snapshot failed'
  /usr/bin/cmp -s "$original_archive" "$verification_root/inputs/LectureBoard-AI-v1.0.0-arm64.zip" \
    && /usr/bin/cmp -s "$original_checksum" "$verification_root/inputs/SHA256SUMS" \
    && /usr/bin/cmp -s "$original_sbom" "$verification_root/inputs/SBOM.spdx.json" \
    && /usr/bin/cmp -s "$original_provenance" "$verification_root/inputs/provenance.json" \
    && /usr/bin/cmp -s "$original_test" "$verification_root/inputs/$release_test_evidence_name" \
    || die 'release inputs changed while they were snapshotted'
  archive="$verification_root/inputs/LectureBoard-AI-v1.0.0-arm64.zip"
  checksum="$verification_root/inputs/SHA256SUMS"
  sbom="$verification_root/inputs/SBOM.spdx.json"
  provenance="$verification_root/inputs/provenance.json"
  expected_test="$verification_root/inputs/$release_test_evidence_name"
  release_test_evidence_is_valid "$expected_test" "$expected_commit" || die 'release test evidence is invalid'
  checksum_manifest_is_exact "$checksum" || die 'checksum file must contain the exact four release payload records'
  expected_sha="$(/usr/bin/awk -v name="${archive##*/}" 'NF == 2 && $2 == name { print $1 }' "$checksum")"; expected_test_sha="$(/usr/bin/awk -v name="$release_test_evidence_name" 'NF == 2 && $2 == name { print $1 }' "$checksum")"; expected_sbom_sha="$(/usr/bin/awk '$2 == "SBOM.spdx.json" { print $1 }' "$checksum")"; expected_provenance_sha="$(/usr/bin/awk '$2 == "provenance.json" { print $1 }' "$checksum")"; [[ "$expected_sha" =~ ^[0-9a-f]{64}$ && "$expected_test_sha" =~ ^[0-9a-f]{64}$ && "$expected_sbom_sha" =~ ^[0-9a-f]{64}$ && "$expected_provenance_sha" =~ ^[0-9a-f]{64}$ ]] || die 'checksum file malformed'; [[ "$(sha256 "$archive")" == "$expected_sha" ]] || die 'archive checksum mismatch'; [[ "$(sha256 "$expected_test")" == "$expected_test_sha" ]] || die 'release test evidence checksum mismatch'; [[ "$(sha256 "$sbom")" == "$expected_sbom_sha" ]] || die 'SBOM checksum mismatch'; [[ "$(sha256 "$provenance")" == "$expected_provenance_sha" ]] || die 'provenance checksum mismatch'; /usr/bin/python3 -I -m json.tool "$sbom" >/dev/null || die 'SBOM invalid'; /usr/bin/python3 -I -m json.tool "$provenance" >/dev/null || die 'provenance invalid';
  release_sbom_is_valid "$sbom" "$expected_commit" "$expected_sha" \
    || die 'SBOM schema or metadata is not exact'
  release_provenance_is_valid \
    "$provenance" "$expected_commit" "$expected_sha" "$expected_test_sha" \
    || die 'provenance schema or metadata is not exact'
  [[ "$(/usr/bin/plutil -extract schema raw -o - "$provenance" 2>/dev/null)" == 'lectureboard.no-fee-provenance.v1' ]] || die 'provenance schema is not exact';
  [[ "$(/usr/bin/plutil -extract repository raw -o - "$provenance" 2>/dev/null)" == 'akiyama709/lectureboard-ai' ]] || die 'provenance repository is not exact';
  [[ "$(/usr/bin/plutil -extract tag raw -o - "$provenance" 2>/dev/null)" == "$tag_expected" ]] || die 'provenance tag is not exact';
  expected_tag_object="$(/usr/bin/plutil -extract tagObject raw -o - "$provenance" 2>/dev/null)" || die 'provenance tag object is absent'; oid "$expected_tag_object" tag-object
  [[ "$(/usr/bin/plutil -extract commit raw -o - "$provenance" 2>/dev/null)" == "$expected_commit" ]] || die 'provenance commit is not exact';
  [[ "$(/usr/bin/plutil -extract bundleIdentifier raw -o - "$provenance" 2>/dev/null)" == "$bundle_id" && "$(/usr/bin/plutil -extract version raw -o - "$provenance" 2>/dev/null)" == "$version" ]] || die 'provenance bundle metadata is not exact';
  [[ "$(/usr/bin/plutil -extract architecture raw -o - "$provenance" 2>/dev/null)" == arm64 && "$(/usr/bin/plutil -extract signature raw -o - "$provenance" 2>/dev/null)" == 'ad hoc' ]] || die 'provenance signing metadata is not exact';
  [[ "$(/usr/bin/plutil -extract hardenedRuntime raw -o - "$provenance" 2>/dev/null)" == true ]] || die 'provenance hardened-runtime claim is absent';
  [[ "$(/usr/bin/plutil -extract configuration raw -o - "$provenance" 2>/dev/null)" == Release && -n "$(/usr/bin/plutil -extract toolchain raw -o - "$provenance" 2>/dev/null)" ]] || die 'provenance toolchain binding is absent';
  /usr/bin/python3 -I - "$provenance" <<'PY'
import hashlib,json,sys
d=json.load(open(sys.argv[1]))
keys=["com.apple.security.automation.apple-events","com.apple.security.device.audio-input"]
e=d.get("entitlements")
assert isinstance(e,dict) and set(e)=={"keys","canonicalJsonSha256"} and e["keys"]==keys
canonical=json.dumps({key:True for key in keys},sort_keys=True,separators=(",",":"))
assert e["canonicalJsonSha256"]==hashlib.sha256(canonical.encode()).hexdigest()
PY
  [[ $? == 0 ]] || die 'provenance entitlement binding is not exact';
  [[ "$(/usr/bin/plutil -extract testResult.name raw -o - "$provenance" 2>/dev/null)" == "$release_test_evidence_name" && "$(/usr/bin/plutil -extract testResult.sha256 raw -o - "$provenance" 2>/dev/null)" == "$(sha256 "$expected_test")" ]] || die 'provenance test-result binding is not exact';
  [[ "$(/usr/bin/plutil -extract archive.name raw -o - "$provenance" 2>/dev/null)" == "${archive##*/}" && "$(/usr/bin/plutil -extract archive.sha256 raw -o - "$provenance" 2>/dev/null)" == "$(lower "$expected_sha")" ]] || die 'provenance archive binding is not exact';
  archive_central_directory_is_safe_and_portable "$archive" "$product.app" \
    || die 'ZIP central-directory preflight failed'
  ditto_root="$verification_root/ditto"; unzip_root="$verification_root/unzip"; /bin/mkdir "$ditto_root" "$unzip_root" || die 'ZIP extraction roots could not be created'
  /usr/bin/ditto -x -k --norsrc --noqtn "$archive" "$ditto_root" || die 'ditto ZIP extraction failed'; [[ -d "$ditto_root/$product.app" ]] || die 'ditto-extracted application missing'; [[ -z "$(/usr/bin/find "$ditto_root" -type l -print -quit)" ]] || die 'ditto extraction contains a symbolic link'; verify_app "$ditto_root/$product.app" "$expected_commit" "$expected_tag_object";
  /usr/bin/unzip -qq "$archive" -d "$unzip_root" || die 'unzip extraction failed'; [[ -d "$unzip_root/$product.app" ]] || die 'unzip-extracted application missing'; [[ -z "$(/usr/bin/find "$unzip_root" -type l -print -quit)" ]] || die 'unzip extraction contains a symbolic link'; verify_app "$unzip_root/$product.app" "$expected_commit" "$expected_tag_object";
  exe_sha="$(sha256 "$ditto_root/$product.app/Contents/MacOS/$product")"; [[ "$(sha256 "$unzip_root/$product.app/Contents/MacOS/$product")" == "$exe_sha" ]] || die 'portable extraction executable bytes differ'; [[ "$(/usr/bin/plutil -extract executableSha256 raw -o - "$provenance" 2>/dev/null)" == "$exe_sha" ]] || die 'provenance executable binding is not exact';
  [[ "$(/usr/bin/plutil -extract spdxVersion raw -o - "$sbom" 2>/dev/null)" == 'SPDX-2.3' && "$(/usr/bin/plutil -extract documentNamespace raw -o - "$sbom" 2>/dev/null)" == "https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/SBOM.spdx.json#$expected_commit" && "$(/usr/bin/plutil -extract packages.0.name raw -o - "$sbom" 2>/dev/null)" == "$product" && "$(/usr/bin/plutil -extract packages.0.versionInfo raw -o - "$sbom" 2>/dev/null)" == "$version" && "$(/usr/bin/plutil -extract packages.0.licenseDeclared raw -o - "$sbom" 2>/dev/null)" == MIT && "$(/usr/bin/plutil -extract packages.0.checksums.0.algorithm raw -o - "$sbom" 2>/dev/null)" == SHA256 && "$(/usr/bin/plutil -extract packages.0.checksums.0.checksumValue raw -o - "$sbom" 2>/dev/null)" == "$expected_sha" ]] || die 'SBOM package metadata is not exact';
  [[ "$(/usr/bin/find "$ditto_root" -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 1 && "$(/usr/bin/find "$unzip_root" -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l | /usr/bin/tr -d ' ')" == 1 ]] || die 'ZIP contains multiple root entries'
  /usr/bin/cmp -s "$original_archive" "$archive" \
    && /usr/bin/cmp -s "$original_checksum" "$checksum" \
    && /usr/bin/cmp -s "$original_sbom" "$sbom" \
    && /usr/bin/cmp -s "$original_provenance" "$provenance" \
    && /usr/bin/cmp -s "$original_test" "$expected_test" \
    || die 'release inputs changed during verification'
  /usr/bin/printf '%s\n' 'no-fee v1 release verification passed'
}

compare_public_release() {
  local approved="$1" downloaded="$2" metadata="$3" refs_path="$4" expected_commit="$5"
  local name expected_sha expected_tag_object approved_physical downloaded_physical
  local original_approved original_downloaded original_metadata original_refs
  oid "$expected_commit" commit
  approved_physical="$(cd -- "$approved" 2>/dev/null && /bin/pwd -P)" \
    || die 'approved release directory could not be resolved'
  downloaded_physical="$(cd -- "$downloaded" 2>/dev/null && /bin/pwd -P)" \
    || die 'public release directory could not be resolved'
  [[ "$approved_physical" != / && "$downloaded_physical" != / \
    && "$approved_physical" != "$downloaded_physical" ]] \
    || die 'approved and public release directories must be distinct physical directories'
  approved="$approved_physical"
  downloaded="$downloaded_physical"
  release_directory_has_exact_assets "$approved" \
    || die 'approved release asset set is not exact'
  release_directory_has_exact_assets "$downloaded" \
    || die 'public release asset set is not exact'
  release_asset_sizes_are_bounded "$approved"
  release_asset_sizes_are_bounded "$downloaded"
  bounded_regular "$metadata" public-release-metadata 4194304
  bounded_regular "$refs_path" public-tag-refs 4096
  original_approved="$approved"; original_downloaded="$downloaded"
  original_metadata="$metadata"; original_refs="$refs_path"
  comparison_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-public-compare.XXXXXX)" \
    || die 'public comparison root failed'
  trap '[[ -n "${comparison_root:-}" && -d "$comparison_root" ]] && /usr/bin/find "$comparison_root" -depth -delete' RETURN
  /bin/mkdir "$comparison_root/approved" "$comparison_root/downloaded" \
    || die 'public comparison snapshot roots failed'
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$(/usr/bin/stat -f '%d:%i' "$original_approved/$name")" \
      != "$(/usr/bin/stat -f '%d:%i' "$original_downloaded/$name")" ]] \
      || die 'approved and public assets must not share one inode'
    /bin/cp -X "$original_approved/$name" "$comparison_root/approved/$name" \
      || die 'approved release snapshot failed'
    /bin/cp -X "$original_downloaded/$name" "$comparison_root/downloaded/$name" \
      || die 'public release snapshot failed'
    /usr/bin/cmp -s "$original_approved/$name" "$comparison_root/approved/$name" \
      && /usr/bin/cmp -s "$original_downloaded/$name" "$comparison_root/downloaded/$name" \
      || die 'release assets changed while they were snapshotted'
  done <<<"$release_asset_name_list"
  /bin/cp -X "$original_metadata" "$comparison_root/public-release.json" \
    || die 'public release metadata snapshot failed'
  /bin/cp -X "$original_refs" "$comparison_root/public-tag-refs.txt" \
    || die 'public tag refs snapshot failed'
  /usr/bin/cmp -s "$original_metadata" "$comparison_root/public-release.json" \
    && /usr/bin/cmp -s "$original_refs" "$comparison_root/public-tag-refs.txt" \
    || die 'public metadata changed while it was snapshotted'
  approved="$comparison_root/approved"
  downloaded="$comparison_root/downloaded"
  metadata="$comparison_root/public-release.json"
  refs_path="$comparison_root/public-tag-refs.txt"
  public_release_metadata_is_valid \
    "$metadata" "$expected_commit" "$approved" "$downloaded" \
    || die 'public GitHub release metadata is not exact'
  expected_tag_object="$(/usr/bin/plutil -extract tagObject raw -o - \
    "$approved/provenance.json" 2>/dev/null)" \
    || die 'approved provenance tag object is absent'
  oid "$expected_tag_object" tag-object
  public_tag_refs_are_valid "$refs_path" "$expected_commit" "$expected_tag_object" \
    || die 'public annotated tag refs do not resolve to the approved commit'
  checksum_manifest_is_exact "$approved/SHA256SUMS" \
    || die 'approved checksum manifest is not exact'
  /usr/bin/cmp -s -- "$approved/SHA256SUMS" "$downloaded/SHA256SUMS" \
    || die 'public checksum manifest bytes differ from approved local bytes'
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    expected_sha="$(/usr/bin/awk -v name="$name" 'NF == 2 && $2 == name { print $1 }' "$approved/SHA256SUMS")"
    [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die 'approved checksum manifest is malformed'
    [[ "$(sha256 "$approved/$name")" == "$expected_sha" ]] \
      || die 'approved release payload checksum mismatch'
    [[ "$(sha256 "$downloaded/$name")" == "$expected_sha" ]] \
      || die 'public release payload checksum mismatch'
    /usr/bin/cmp -s -- "$approved/$name" "$downloaded/$name" \
      || die 'public release payload bytes differ from approved local bytes'
  done <<<"$release_payload_name_list"
  release_directory_has_exact_assets "$original_approved" \
    && release_directory_has_exact_assets "$original_downloaded" \
    || die 'release asset inventory changed during public comparison'
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    /usr/bin/cmp -s "$original_approved/$name" "$approved/$name" \
      && /usr/bin/cmp -s "$original_downloaded/$name" "$downloaded/$name" \
      || die 'release asset bytes changed during public comparison'
  done <<<"$release_asset_name_list"
  /usr/bin/cmp -s "$original_metadata" "$metadata" \
    && /usr/bin/cmp -s "$original_refs" "$refs_path" \
    || die 'public metadata changed during comparison'
  /usr/bin/printf '%s\n' 'provided release asset set exactly matches approved local bytes'
}

verify_public_release() {
  local output_parent output_leaf approved_snapshot downloaded metadata refs receipt acquired_at
  local name maximum rename_helper public_home helper_source original_approved
  local acquired_downloaded acquired_metadata acquired_refs
  local parent_identity stage_identity parent_device parent_inode stage_device stage_inode
  abs_dir "$source_dir" source-dir
  abs_dir "$approved_dir" approved-dir
  abs_dir "$output_dir" output-dir
  oid "$commit" commit
  release_tool_matches_commit "$source_dir" "$commit" \
    || die 'release tool does not match the public-verification commit'
  original_approved="$(cd -- "$approved_dir" 2>/dev/null && /bin/pwd -P)" \
    || die 'approved release directory could not be resolved'
  [[ "$original_approved" != / ]] \
    || die 'approved release directory must not resolve to root'
  release_directory_has_exact_assets "$original_approved" \
    || die 'approved release asset set is not exact'
  release_asset_sizes_are_bounded "$original_approved"
  [[ ! -e "$output_dir" && ! -L "$output_dir" ]] \
    || die 'public-verification output directory must not already exist'
  output_parent="$(/usr/bin/dirname -- "$output_dir")"
  output_leaf="${output_dir##*/}"
  [[ -n "$output_leaf" && -d "$output_parent" && ! -L "$output_parent" ]] \
    || die 'public-verification output parent is invalid'
  public_parent_physical="$(cd -- "$output_parent" && /bin/pwd -P)" \
    || die 'public-verification output parent could not be resolved'
  output_dir="$public_parent_physical/$output_leaf"
  [[ ! -e "$output_dir" && ! -L "$output_dir" ]] \
    || die 'resolved public-verification output directory must not already exist'
  public_stage="$(/usr/bin/mktemp -d \
    "$public_parent_physical/.lectureboard-v1-public.XXXXXX")" \
    || die 'public-verification staging directory could not be created'
  parent_identity="$(directory_identity "$public_parent_physical")" \
    || die 'public-verification output-parent identity could not be captured'
  stage_identity="$(directory_identity "$public_stage")" \
    || die 'public-verification staging-directory identity could not be captured'
  parent_device="${parent_identity% *}"; parent_inode="${parent_identity#* }"
  stage_device="${stage_identity% *}"; stage_inode="${stage_identity#* }"
  public_acquisition="$(/usr/bin/mktemp -d \
    /private/tmp/lectureboard-v1-public-acquisition.XXXXXX)" \
    || die 'public-verification acquisition root could not be created'
  acquired_downloaded="$public_acquisition/assets"
  acquired_metadata="$public_acquisition/public-release.json"
  acquired_refs="$public_acquisition/public-tag-refs.txt"
  downloaded="$public_stage/assets"
  approved_snapshot="$public_stage/approved"
  metadata="$public_stage/public-release.json"
  refs="$public_stage/public-tag-refs.txt"
  receipt="$public_stage/verification-receipt.json"
  public_home="$public_acquisition/empty-home"
  /bin/mkdir "$approved_snapshot" "$downloaded" "$acquired_downloaded" "$public_home" \
    || die 'public-verification directories could not be created'
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    /bin/cp -X "$original_approved/$name" "$approved_snapshot/$name" \
      || die 'approved release snapshot failed'
    /usr/bin/cmp -s "$original_approved/$name" "$approved_snapshot/$name" \
      || die 'approved release asset changed while it was snapshotted'
  done <<<"$release_asset_name_list"
  release_directory_has_exact_assets "$approved_snapshot" \
    || die 'approved release snapshot is not exact'
  release_asset_sizes_are_bounded "$approved_snapshot"
  helper_source="$public_stage/release-exclusive-rename.c"
  git_read -C "$source_dir" show \
    "$commit:scripts/release-exclusive-rename.c" >"$helper_source" \
    || die 'committed public-verification helper source could not be materialized'
  bounded_regular "$helper_source" public-verification-helper-source 1048576
  public_helper="$(/usr/bin/mktemp \
    /private/tmp/lectureboard-v1-public-rename.XXXXXX)" \
    || die 'public-verification handoff helper path could not be created'
  rename_helper="$public_helper"
  /usr/bin/clang -std=c17 -Wall -Wextra -Werror -O2 \
    "$helper_source" -o "$rename_helper" \
    || die 'exclusive public-verification handoff helper could not be compiled'
  /usr/bin/env -i HOME="$public_home" PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
    /usr/bin/curl --disable --fail --silent --show-error --location \
      --proto '=https' --tlsv1.2 --max-redirs 5 --connect-timeout 20 --max-time 300 \
      --max-filesize 4194304 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      --output "$acquired_metadata" \
      'https://api.github.com/repos/akiyama709/lectureboard-ai/releases/tags/v1.0.0' \
    || die 'unauthenticated public release metadata download failed'
  bounded_regular "$acquired_metadata" public-release-metadata 4194304
  while IFS=' ' read -r name maximum; do
    [[ -n "$name" && -n "$maximum" ]] || continue
    /usr/bin/env -i HOME="$public_home" PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
      /usr/bin/curl --disable --fail --silent --show-error --location \
        --proto '=https' --tlsv1.2 --max-redirs 5 --connect-timeout 20 --max-time 900 \
        --max-filesize "$maximum" --output "$acquired_downloaded/$name" \
        "https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/$name" \
      || die "unauthenticated public asset download failed: $name"
  done <<'ASSETS'
LectureBoard-AI-v1.0.0-arm64.zip 536870912
LectureBoard-AI-v1.0.0-test-results.json 32768
SBOM.spdx.json 1048576
SHA256SUMS 4096
provenance.json 1048576
ASSETS
  release_directory_has_exact_assets "$acquired_downloaded" \
    || die 'downloaded public release asset set is not exact'
  release_asset_sizes_are_bounded "$acquired_downloaded"
  (
    cd -- "$public_home"
    git_read ls-remote \
      'https://github.com/akiyama709/lectureboard-ai.git' \
      'refs/tags/v1.0.0' 'refs/tags/v1.0.0^{}'
  ) >"$acquired_refs" || die 'unauthenticated public tag lookup failed'
  bounded_regular "$acquired_refs" public-tag-refs 4096
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    /bin/cp -X "$acquired_downloaded/$name" "$downloaded/$name" \
      || die 'public release asset snapshot failed'
  done <<<"$release_asset_name_list"
  /bin/cp -X "$acquired_metadata" "$metadata" \
    || die 'public release metadata snapshot failed'
  /bin/cp -X "$acquired_refs" "$refs" \
    || die 'public tag refs snapshot failed'
  public_inputs_match_snapshot \
    "$acquired_downloaded" "$downloaded" \
    "$acquired_metadata" "$metadata" "$acquired_refs" "$refs" \
    || die 'public inputs changed while the verification snapshot was created'
  release_asset_sizes_are_bounded "$downloaded"
  bounded_regular "$metadata" public-release-metadata 4194304
  bounded_regular "$refs" public-tag-refs 4096
  compare_public_release "$approved_snapshot" "$downloaded" "$metadata" "$refs" "$commit"
  verify_archive \
    "$downloaded/LectureBoard-AI-v1.0.0-arm64.zip" "$commit" \
    "$downloaded/SHA256SUMS" "$downloaded/SBOM.spdx.json" \
    "$downloaded/provenance.json" \
    "$downloaded/$release_test_evidence_name"
  public_inputs_match_snapshot \
    "$acquired_downloaded" "$downloaded" \
    "$acquired_metadata" "$metadata" "$acquired_refs" "$refs" \
    || die 'public inputs changed after archive verification'
  acquired_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    || die 'public-verification completion time unavailable'
  /usr/bin/python3 -I - "$receipt" "$commit" "$acquired_at" \
    "$(sha256 "$metadata")" "$(sha256 "$refs")" \
    "$(sha256 "$downloaded/LectureBoard-AI-v1.0.0-arm64.zip")" <<'PY'
import json,sys
path,commit,acquired,metadata_digest,refs_digest,archive_digest=sys.argv[1:]
data={"schema":"lectureboard.public-verification-receipt.v1","repository":"akiyama709/lectureboard-ai","release":"v1.0.0","sourceCommit":commit,"acquiredAt":acquired,"authentication":"none","releaseMetadataSha256":metadata_digest,"tagRefsSha256":refs_digest,"archiveSha256":archive_digest,"result":"Passed"}
with open(path,"x",encoding="utf-8") as stream:
 json.dump(data,stream,sort_keys=True,separators=(",",":")); stream.write("\n")
PY
  public_inputs_match_snapshot \
    "$acquired_downloaded" "$downloaded" \
    "$acquired_metadata" "$metadata" "$acquired_refs" "$refs" \
    || die 'public inputs changed while the verification receipt was created'
  release_directory_has_exact_assets "$original_approved" \
    || die 'approved release asset set changed during public verification'
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    /usr/bin/cmp -s "$original_approved/$name" "$approved_snapshot/$name" \
      || die 'approved release asset bytes changed during public verification'
  done <<<"$release_asset_name_list"
  compare_public_release "$approved_snapshot" "$downloaded" "$metadata" "$refs" "$commit"
  /usr/bin/find "$public_acquisition" -depth -delete \
    || die 'public-verification acquisition root could not be removed'
  public_acquisition=''
  compare_public_release "$approved_snapshot" "$downloaded" "$metadata" "$refs" "$commit"
  /bin/unlink "$helper_source" \
    || die 'public-verification helper source could not be removed'
  /usr/bin/find "$approved_snapshot" -depth -delete \
    || die 'approved release snapshot could not be removed'
  "$rename_helper" "$public_stage" "$output_dir" \
    "$parent_device" "$parent_inode" "$stage_device" "$stage_inode" \
    || die 'public-verification evidence could not be published exclusively'
  public_stage=''
  if /bin/unlink "$public_helper"; then
    public_helper=''
  else
    /usr/bin/printf '%s\n' \
      'warning: public-verification handoff helper cleanup will be retried on exit' >&2
  fi
  /usr/bin/printf 'unauthenticated public v1.0.0 verification passed: %s\n' "$output_dir"
}

cleanup_release_temporaries() {
  local candidate
  for candidate in "${temp:-}" "${handoff_root:-}" "${verification_root:-}" \
    "${comparison_root:-}" "${public_acquisition:-}" "${query_root:-}" \
    "${digest_root:-}"; do
    [[ -z "$candidate" || ! -d "$candidate" ]] && continue
    case "$candidate" in
      /private/tmp/lectureboard-v1-build.*|/private/tmp/lectureboard-v1-handoff.*|/private/tmp/lectureboard-v1-evidence-run.*|/private/tmp/lectureboard-v1-verify.*|/private/tmp/lectureboard-v1-public-compare.*|/private/tmp/lectureboard-v1-public-acquisition.*|/private/tmp/lectureboard-result-materialize.*|/private/tmp/lectureboard-result-query.*|/private/tmp/lectureboard-result-pair.*)
        /usr/bin/find "$candidate" -depth -delete
        ;;
      *) /usr/bin/printf '%s\n' 'refusing to clean unexpected release temporary path' >&2 ;;
    esac
  done
  if [[ -z "${published_evidence_identity:-}" \
    && -n "${evidence_stage:-}" && -n "${evidence_parent_physical:-}" \
    && "$(/usr/bin/dirname -- "$evidence_stage")" == "$evidence_parent_physical" \
    && "${evidence_stage##*/}" == .lectureboard-v1-evidence.* ]]; then
    if [[ -z "${parent_identity:-}" || -z "${stage_identity:-}" ]] \
      || ! delete_directory_with_identity "$evidence_parent_physical" \
        "$parent_identity" "$evidence_stage" "$stage_identity"; then
      /usr/bin/printf '%s\n' \
        'warning: refusing to clean evidence staging without its exact known identity' >&2
    fi
  fi
  if [[ -n "${published_evidence_identity:-}" ]] \
    && ! cleanup_known_evidence_handoff \
      "${published_evidence_parent:-}" "${published_evidence_parent_identity:-}" \
      "${published_evidence_stage:-}" "${published_evidence_dir:-}" \
      "$published_evidence_identity" "${published_evidence_parent_fd:-}" \
      "${published_evidence_stage_fd:-}"; then
    /usr/bin/printf '%s\n' \
      'warning: refusing to clean evidence handoff without its exact known identity' >&2
  fi
  if [[ -n "${release_stage:-}" && -n "${release_parent_physical:-}" \
    && -d "$release_stage" && ! -L "$release_stage" \
    && "$(/usr/bin/dirname -- "$release_stage")" == "$release_parent_physical" \
    && "${release_stage##*/}" == .lectureboard-v1-release.* ]]; then
    /usr/bin/find "$release_stage" -depth -delete
  fi
  if [[ -n "${public_stage:-}" && -n "${public_parent_physical:-}" \
    && -d "$public_stage" && ! -L "$public_stage" \
    && "$(/usr/bin/dirname -- "$public_stage")" == "$public_parent_physical" \
    && "${public_stage##*/}" == .lectureboard-v1-public.* ]]; then
    /usr/bin/find "$public_stage" -depth -delete
  fi
  if [[ -n "${public_helper:-}" && -f "$public_helper" && ! -L "$public_helper" \
    && "$(/usr/bin/dirname -- "$public_helper")" == /private/tmp \
    && "${public_helper##*/}" == lectureboard-v1-public-rename.* ]]; then
    /bin/unlink "$public_helper"
  fi
}
trap cleanup_release_temporaries EXIT

internal_environment_flag='--lectureboard-internal-sanitized-no-fee-release'
current_user="$(/usr/bin/id -un)" || die 'release user could not be identified'
trusted_home="$(/usr/bin/id -P "$current_user" | /usr/bin/awk -F: 'NF >= 9 { print $9 }')" \
  || die 'release home directory could not be identified'
[[ "$trusted_home" == /* && -d "$trusted_home" && ! -L "$trusted_home" ]] \
  || die 'release home directory is invalid'
if [[ "${1:-}" != "$internal_environment_flag" ]]; then
  reject_production_overrides
  [[ -z "${LECTUREBOARD_RELEASE_TEST_MODE:-}" ]] \
    || die 'production commands reject fixture mode'
  if /usr/bin/env | /usr/bin/grep '^BASH_FUNC_' >/dev/null; then
    die 'production commands reject exported Bash functions'
  fi
  exec /usr/bin/env -i \
    HOME="$trusted_home" USER="$current_user" LOGNAME="$current_user" \
    TMPDIR=/private/tmp PATH="$PATH" LC_ALL=C \
    /bin/bash -p "$0" "$internal_environment_flag" "$@"
fi
shift
unexpected_environment="$(/usr/bin/env | /usr/bin/awk -F= '
  $1 != "HOME" && $1 != "USER" && $1 != "LOGNAME" &&
  $1 != "TMPDIR" && $1 != "PATH" && $1 != "LC_ALL" &&
  $1 != "PWD" && $1 != "SHLVL" && $1 != "_" { print $1 }
')"
[[ -z "$unexpected_environment" && "$HOME" == "$trusted_home" \
  && "$USER" == "$current_user" && "$LOGNAME" == "$current_user" \
  && "$TMPDIR" == /private/tmp ]] \
  || die 'sanitized release environment is invalid'

command="${1:-}"; [[ -n "$command" ]] || { usage >&2; exit 64; }; unset source_dir output_dir approved_dir downloaded_dir app build_receipt commit tag test_result test_result_bundle gate_log checksum sbom provenance release_metadata tag_refs; tag_expected='v1.0.0'; parse_args "$@"; [[ -z "${commit:-}" ]] || commit="$(lower "$commit")"; case "$command" in
  evidence) [[ -n "${source_dir:-}" && -n "${output_dir:-}" && -n "${commit:-}" ]] || { usage >&2; exit 64; }; release_tool_matches_commit "$source_dir" "$commit" || die 'release tool does not match the evidence commit'; generate_release_evidence;;
  prepare) [[ -n "${source_dir:-}" && -n "${output_dir:-}" && -n "${commit:-}" && -n "${tag:-}" && -n "${test_result:-}" && -n "${test_result_bundle:-}" && -n "${gate_log:-}" ]] || { usage >&2; exit 64; }; release_tool_matches_commit "$source_dir" "$commit" || die 'release tool does not match the approved commit'; prepare_release;;
  verify) [[ -n "${archive:-}" && -n "${checksum:-}" && -n "${sbom:-}" && -n "${provenance:-}" && -n "${test_result:-}" && -n "${commit:-}" ]] || { usage >&2; exit 64; }; verify_archive "$archive" "$commit" "$checksum" "$sbom" "$provenance" "$test_result";;
  compare-public) [[ -n "${approved_dir:-}" && -n "${downloaded_dir:-}" && -n "${release_metadata:-}" && -n "${tag_refs:-}" && -n "${commit:-}" ]] || { usage >&2; exit 64; }; compare_public_release "$approved_dir" "$downloaded_dir" "$release_metadata" "$tag_refs" "$commit";;
  verify-public) [[ -n "${source_dir:-}" && -n "${approved_dir:-}" && -n "${output_dir:-}" && -n "${commit:-}" ]] || { usage >&2; exit 64; }; verify_public_release;;
  *) usage >&2; exit 64;; esac
