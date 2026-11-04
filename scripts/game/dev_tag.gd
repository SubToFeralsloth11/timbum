class_name DevTag
## The developer tag: the only thing that turns on the admin panel (cheats) and the Dev Pack.
## A profile is a developer's when its `dev_tag` ({id, sig}) carries an RSA-SHA256 signature of
## MESSAGE_PREFIX + id that checks out against PUBLIC_KEY. Only the public key ships; the private
## key stays with the owner (outside the repo), so a hand-edited profile.json can't make a tag.
## The tag travels inside progress exports, so whoever holds the owner's export file is the developer.

const MESSAGE_PREFIX := "timbum-dev-tag:"
const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwjr9FwQOOlf+csfhRYm8
bgBtMjB+gSJFX2ZKwhCwknOgelXf/A7oeVBMrbntIzhWU+NolLB356vCUU0Yad2w
PIl+hfD0wwBPlFiSGAxovNgdmmYgAP2OFkwQv+qYwbMtUIhUv7Yw4oGM1D7Y4VMR
9VLlB3P2nnJ5gYXMkyhTFzaMS3sTdjOcXAJNHY/8bHYBnj29E3UFlPNE1Ttg0RGv
HTL3whAIgI/748x9eZ03j1BQv72iFeGkY9FdX0QERJhXQCc54QG/PnKRXAYOZUyE
9Xn5uHlZj3lSKpMdXh/21qLkYVwX6B5cH2OjRTTYz3/AZUEHEw+wcqT+y2p8xpxZ
9QIDAQAB
-----END PUBLIC KEY-----
"""
## An RSA-2048 signature in base64 is 344 characters; anything far off isn't one.
const MAX_SIG_LENGTH := 1024

static var _key: CryptoKey


## True when `tag` is a {id, sig} dictionary whose signature verifies.
static func verify(tag: Variant) -> bool:
	if typeof(tag) != TYPE_DICTIONARY:
		return false
	var id: Variant = tag.get("id")
	var sig_text: Variant = tag.get("sig")
	if typeof(id) != TYPE_STRING or typeof(sig_text) != TYPE_STRING:
		return false
	if (id as String).is_empty() or (sig_text as String).is_empty() or (sig_text as String).length() > MAX_SIG_LENGTH:
		return false
	var sig := Marshalls.base64_to_raw(sig_text)
	if sig.is_empty():
		return false
	if _key == null:
		_key = CryptoKey.new()
		if _key.load_from_string(PUBLIC_KEY, true) != OK:
			push_error("DevTag: the public key didn't load")
			return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, (MESSAGE_PREFIX + id).sha256_buffer(), sig, _key)
