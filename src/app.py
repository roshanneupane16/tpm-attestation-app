#!/usr/bin/env python3
from flask import Flask, request, jsonify
from subprocess import Popen, PIPE
from urllib.parse import unquote
import binascii
import base64
import sys
import os

app = Flask(__name__)

def load_symmetric_key():
    """Load the decrypted symmetric key from runtime location"""
    try:
        with open('/run/symmetric_key', 'r') as f:
            key_b64 = f.read().strip()
        return binascii.hexlify(base64.b64decode(key_b64)).decode()
    except FileNotFoundError:
        return None

@app.route('/', methods=['GET'])
def decrypt():
    """Decrypt ciphertext using symmetric key"""
    ciphertext = request.args.get('ciphertext') or request.args.get('text')
    
    if not ciphertext:
        return jsonify({"error": "Missing ciphertext parameter"}), 400
    
    # Load symmetric key
    key = load_symmetric_key()
    if not key:
        return jsonify({"error": "Symmetric key not available"}), 500
    
    try:
        # URL decode the ciphertext
        text = unquote(ciphertext)
        
        # Extract IV (first 32 chars) and encrypted data
        if len(text) < 32:
            return jsonify({"error": "Invalid ciphertext format"}), 400
            
        iv = text[:32]
        encrypted_data = text[32:]
        
        # Decrypt using OpenSSL
        p = Popen([
            'openssl', 'enc', '-d', '-aes-256-cbc', '-base64', 
            '-K', key, '-iv', iv, '-A'
        ], stdout=PIPE, stdin=PIPE, stderr=PIPE, text=True)
        
        result, error = p.communicate(encrypted_data + "\n")
        
        if p.returncode != 0:
            return jsonify({"error": f"Decryption failed: {error}"}), 500
            
        return result
        
    except Exception as e:
        return jsonify({"error": f"Processing error: {str(e)}"}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    key_available = os.path.exists('/run/symmetric_key')
    return jsonify({
        "status": "healthy",
        "key_available": key_available
    })

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80, debug=False)
