# Repository Notes

- Keep simple and web setup logic explicit. Do not store or infer an install mode.
- `template/simple/.container/init.sh` and `template/web/.container/init.sh` are intentionally separate. When changing shared initialization behavior, review and update both scripts.
- Prefer small duplication over a shared mode-aware init abstraction.
