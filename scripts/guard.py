from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
errors = []
for p in (root / 'Sources').rglob('*.swift'):
    text = p.read_text()
    if len(text.splitlines()) > 260:
        errors.append(f'{p.name}: split by responsibility; exceeds 260 lines')
    if 'URLSession' in text and p.name != 'TranslationClient.swift':
        errors.append(f'{p.name}: networking belongs in TranslationClient')
    if re.search(r'print\(|NSLog\(', text):
        errors.append(f'{p.name}: no production output of text or credentials')
    if 'SecItem' in text and p.name != 'CredentialStore.swift':
        errors.append(f'{p.name}: Keychain belongs in CredentialStore')
for error in errors: print(error)
if errors: raise SystemExit(1)
print('Project boundaries passed')
