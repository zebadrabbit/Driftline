## Deterministic hashing utilities.
##
## Avoid String.hash() for replay/network contracts.

class_name DriftHash


static func sha256_bytes_from_string(s: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(String(s).to_utf8_buffer())
	return ctx.finish()


static func int31_from_sha256_bytes(bytes: PackedByteArray) -> int:
	# Deterministic 31-bit positive int derived from SHA256 digest.
	# Uses the first 4 bytes as big-endian u32 then masks to 31 bits.
	if bytes == null or bytes.size() < 4:
		return 0
	var u32: int = (int(bytes[0]) << 24) | (int(bytes[1]) << 16) | (int(bytes[2]) << 8) | int(bytes[3])
	return int(u32 & 0x7fffffff)


static func int31_from_string_sha256(s: String) -> int:
	return int31_from_sha256_bytes(sha256_bytes_from_string(s))
