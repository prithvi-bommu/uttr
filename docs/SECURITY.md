# Security

## API key storage

Uttr stores optional cloud provider API keys as **plaintext** in:

```
~/Library/Application Support/Uttr/config.json
```

This is an intentional v1 design decision. The file is created with restricted permissions (`0600` — owner read/write only), but the keys are not encrypted.

### Mitigations

- The configuration file is created with `0600` permissions
- The parent directory is created with `0700` permissions
- API keys are never logged, displayed in accessibility labels, or included in error messages
- Keys are sent only to the configured provider's HTTPS endpoint when text polish is enabled
- Cloud polish is disabled by default

### Recommendations

- Use a provider API key with a spending limit
- Do not use a high-privilege or admin-level key
- If you share your Mac with other users, be aware they could read the file if they have admin access

## Network security

- All provider connections use HTTPS with ephemeral URLSession configuration
- No caching of network responses
- No automatic retries
- 8-second timeout on all provider requests

## Hardened Runtime

Release builds enable Hardened Runtime. The app does not use App Sandbox because it requires global keyboard event monitoring and cross-application paste.
