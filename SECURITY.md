# Security

Quillmit shells out to local AI CLI tools and local Git. It does not ask for API
keys directly and does not manage provider credentials.

## Reporting Issues

Please report security concerns privately to the repository owner instead of
opening a public issue.

## Safety Notes

- Review generated commit messages before committing.
- Avoid running Quillmit in repositories with secrets in uncommitted diffs unless
  you are comfortable sending that diff context to your selected AI provider.
- Provider CLIs may transmit prompt context to their respective services.
  Quillmit does not redact diffs.
