#!/bin/bash
set -eo pipefail

kms_key_id="$1"
ciphertext="$2"

# Generate RSA key pair for attestation
private_key="$(openssl genrsa 2048 | base64 --wrap 0)"
public_key="$(openssl rsa \
    -pubout \
    -in <(base64 --decode <<< "$private_key") \
    -outform DER \
    2> /dev/null \
    | base64 --wrap 0)"

# Request attestation document with public key
attestation_doc="$(/aws-nitro-tpm-tools/nitro-tpm-attest \
    --public-key <(base64 --decode <<< "$public_key") \
    | base64 --wrap 0)"

# Decrypt with KMS using attestation document
plaintext_cms=$(aws kms decrypt \
    --key-id "$kms_key_id" \
    --recipient "KeyEncryptionAlgorithm=RSAES_OAEP_SHA_256,AttestationDocument=$attestation_doc" \
    --ciphertext-blob fileb://<(base64 --decode <<< "$ciphertext") \
    --output text \
    --query CiphertextForRecipient)

# Decrypt the CMS envelope with private key
openssl cms \
    -decrypt \
    -inkey <(base64 --decode <<< "$private_key") \
    -inform DER \
    -in <(base64 --decode <<< "$plaintext_cms")
