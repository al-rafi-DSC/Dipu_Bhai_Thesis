"""Validate the input hashes and the saved, executed professor-review notebook."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import nbformat

ROOT = Path(__file__).resolve().parents[1]


def verify_inputs(root: Path = ROOT) -> dict:
    manifest = json.loads((root / 'data_manifest.json').read_text(encoding='utf-8'))
    for entry in manifest['files']:
        source = (root / entry['path']).resolve()
        if not source.is_relative_to(root.resolve()):
            raise ValueError(f"Input path is outside the repository: {entry['path']}")
        content = source.read_bytes()
        if len(content) != entry['bytes']:
            raise ValueError(f"Input size changed: {entry['path']}")
        if hashlib.sha256(content).hexdigest() != entry['sha256']:
            raise ValueError(f"Input hash changed: {entry['path']}")
    return manifest


def verify_notebook(notebook: nbformat.NotebookNode) -> int:
    nbformat.validate(notebook)
    image_count = 0
    executed_cells = 0
    for position, cell in enumerate(notebook.cells):
        if cell.cell_type != 'code':
            continue
        if cell.execution_count is None:
            raise ValueError(f'Code cell {position} has not been executed.')
        executed_cells += 1
        for output in cell.get('outputs', []):
            if output.output_type == 'error':
                raise ValueError(f"Cell {position}: {output.get('ename')}: {output.get('evalue')}")
            if 'image/png' in output.get('data', {}):
                image_count += 1
    if executed_cells == 0:
        raise ValueError('No executed analysis cells were found.')
    if image_count != 20:
        raise ValueError(f'Expected 20 embedded figures; found {image_count}.')
    return image_count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notebook', type=Path, default=ROOT / 'code/main_5.ipynb')
    args = parser.parse_args()
    manifest = verify_inputs()
    notebook = nbformat.read(args.notebook, as_version=4)
    images = verify_notebook(notebook)
    print(f"Verified {len(manifest['files'])} unchanged input files.")
    print(f'Notebook valid: all code cells executed, no saved errors, {images} embedded figures.')


if __name__ == '__main__':
    main()
