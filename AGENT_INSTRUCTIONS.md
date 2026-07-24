# Agent Guidelines & Best Practices

## ⚠️ File Safety & Cleanliness Rule
- Always check bash commands before execution for unintended quotes, unescaped multiline input, or improper redirection (e.g., `cat > "$file"` vs unquoted heredocs or faulty file names) that could create accidentally named untracked files.
- Never leave weirdly named, corrupted, or unexpected untracked artifacts behind.
- Always check `git status` after performing file operations to ensure the working tree remains clean and free of leftover temporary or corrupted files.
