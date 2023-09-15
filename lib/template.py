from pathlib import Path

from jinja2 import Template

TEMPLATE_ROOT = Path(__file__).parent.parent / 'templates'
TEMPLATE_ARGS = {
    'shieldwall_managed': '# Managed by ShieldWall - DO NOT MODIFY MANUALLY!'
}


def build_template(file: str, args: dict) -> str:
    template_path = f"{TEMPLATE_ROOT}/{file}.j2"
    if not Path(template_path).is_file():
        raise FileNotFoundError(f"Template '{file}' does not exist!")

    with open(template_path, 'r', encoding='utf-8') as tmpl:
        template = Template(
            source=tmpl.read(),
            trim_blocks=True,
            lstrip_blocks=True,
        )

    args = {**TEMPLATE_ARGS, **args}
    return template.render(**args)


if __name__ == '__main__':
    print(build_template(
        file='test',
        args={
            't1': 'first test',
            't2': ['dog', 'bunny'],
        }
    ))
