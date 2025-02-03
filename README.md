# Azure Scripts

This repository hosts sample scripts for exporting information about Azure workloads for offline analysis.

## Configuration

These scripts externalize configuration such as tenant IDs, file paths, and filtering information to a JSON file. Create a new file named `config.json` and populate it with the following structure. Be sure to substitute the values to match your environment.

```json
{
    "tenantId": "abc123",
    "region": "northcentralus",
    "outputFileLocation": "C:\\some\\folder\\"
}
```

For Windows environments, be sure to use the double backslash for all directory paths as shown in the above example.
