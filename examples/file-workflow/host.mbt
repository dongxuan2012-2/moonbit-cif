///|
extern "js" fn host_read(path : String) -> String =
  #| (path) => {
  #|   try {
  #|     if (typeof process.getBuiltinModule !== 'function') throw new Error('Node.js >=22.3 is required');
  #|     const bytes = process.getBuiltinModule('fs').readFileSync(path);
  #|     const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  #|     const sha256 = process.getBuiltinModule('crypto').createHash('sha256').update(bytes).digest('hex');
  #|     return JSON.stringify({ ok: true, text, sha256 });
  #|   } catch (error) {
  #|     return JSON.stringify({ ok: false, error: String(error.message || error) });
  #|   }
  #| }

///|
extern "js" fn host_write_new(path : String, text : String) -> String =
  #| (path, text) => {
  #|   const fs = process.getBuiltinModule('fs');
  #|   let fd = null, created = false;
  #|   try {
  #|     const bytes = Buffer.from(text, 'utf8');
  #|     fd = fs.openSync(path, 'wx');
  #|     created = true;
  #|     fs.writeFileSync(fd, bytes);
  #|     fs.fsyncSync(fd);
  #|     fs.closeSync(fd); fd = null;
  #|     const actual = fs.readFileSync(path);
  #|     if (!actual.equals(bytes)) throw new Error('Output byte readback mismatch');
  #|     const sha256 = process.getBuiltinModule('crypto').createHash('sha256').update(actual).digest('hex');
  #|     return JSON.stringify({ ok: true, sha256, bytes: actual.length, readbackVerified: true });
  #|   } catch (error) {
  #|     if (fd !== null) { try { fs.closeSync(fd); } catch (_) {} }
  #|     let cleanup = '';
  #|     if (created) { try { fs.unlinkSync(path); } catch (e) { cleanup = '; new output cleanup failed: ' + e.message; } }
  #|     return JSON.stringify({ ok: false, error: String(error.message || error) + cleanup });
  #|   }
  #| }

///|
extern "js" fn fail_exit() -> Unit =
  #| () => { process.exitCode = 1; }

///|
extern "js" fn host_text_identity(text : String) -> String =
  #| (text) => {
  #|   try {
  #|     const bytes = Buffer.from(text, 'utf8');
  #|     const sha256 = process.getBuiltinModule('crypto').createHash('sha256').update(bytes).digest('hex');
  #|     return JSON.stringify({ ok: true, sha256, bytes: bytes.length });
  #|   } catch (error) {
  #|     return JSON.stringify({ ok: false, error: String(error.message || error) });
  #|   }
  #| }

///|
fn write_output(
  args : Array[String],
  edited : String,
) -> Json raise WorkflowError {
  let expected_result = if args.length() == 6 {
    let expected = args[5].to_lower()
    if expected.length() != 64 ||
      expected
      .to_array()
      .any(c => !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
      raise Invalid(
        "Expected result SHA256 must contain exactly 64 hexadecimal digits",
      )
    }
    let planned = host_result(host_text_identity(edited))
    if string_field(planned, "sha256") != expected {
      raise Invalid("Expected result SHA256 differs; no output created")
    }
    Some(expected)
  } else {
    None
  }
  let disk = host_result(host_write_new(args[3], edited))
  if expected_result is Some(expected) {
    disk["expectedResultSha256"] = Json::string(expected)
  }
  disk.to_json()
}
