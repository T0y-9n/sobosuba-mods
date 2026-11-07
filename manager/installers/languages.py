"""Build NSIS language tables from the manager's supported locales."""
import json
from pathlib import Path


def generate(nsisdir: Path, output: Path):
    here = Path(__file__).resolve().parent
    languages = json.loads((here/'languages.json').read_text(encoding='utf-8'))
    locales = json.loads((here.parent/'locales.json').read_text(encoding='utf-8'))
    if languages.keys() != locales.keys():
        raise ValueError('Setup languages must match the manager locales.')
    output.mkdir(parents=True, exist_ok=True)
    official = nsisdir/'Contrib/Language files'
    spanish = (official/'SpanishInternational.nsh').read_text(encoding='utf-8-sig')
    spanish = spanish.replace('SpanishInternational', 'SpanishMexico').replace('Spanish (International)', 'Spanish (Mexico)').replace('Español (Alfabetización Internacional)', 'Español (México)')
    (output/'SpanishMexico.nsh').write_text(spanish, encoding='utf-8-sig')
    nlf = (official/'SpanishInternational.nlf').read_text(encoding='utf-8-sig')
    (output/'SpanishMexico.nlf').write_text(nlf.replace('\n3082\n', '\n2058\n'), encoding='utf-8-sig')
    lines = []
    for locale, (name, required, desktop, failed) in languages.items():
        if locale == 'es_MX':
            lines.append(f'!insertmacro MUI_LANGUAGEEX "{output}" "{name}"')
        else:
            lines.append(f'!insertmacro MUI_LANGUAGE "{name}"')
        for key, text in [('SetupRequired', required), ('SetupDesktop', desktop), ('SetupFailed', failed)]:
            escaped = text.replace('$', '$$').replace('"', '$\\"')
            lines.append(f'LangString {key} ${{LANG_{name}}} "{escaped}"')
    path = output/'languages.nsh'
    path.write_text('\n'.join(lines)+'\n', encoding='utf-8-sig')
    return path
