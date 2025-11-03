# TPM Attestation Application

Flask application that provides secure decryption services using AWS Nitro TPM attestation.

## API Endpoints

### Decrypt Data
```
GET /?ciphertext=<ENCRYPTED_DATA>
```

### Health Check
```
GET /health
```

## User Data Format

```json
{
  "key_id": "arn:aws:kms:region:account:key/key-id",
  "ciphertext": "base64-encoded-encrypted-symmetric-key"
}
```

## Ciphertext Format

```
<32-char-hex-iv><base64-encrypted-data>
```
