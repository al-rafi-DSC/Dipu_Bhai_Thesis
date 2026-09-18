"""Execute main_5.ipynb with this interpreter and save all figures in the notebook."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
import tempfile

import nbformat
from nbclient import NotebookClient

from validate_submission import ROOT, verify_inputs, verify_notebook


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'code/main_5.ipynb',
                        help='Notebook output path; the default updates the saved analysis.')
    parser.add_argument('--timeout', type=int, default=600, help='Maximum seconds per cell.')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    verify_inputs()
    notebook = nbformat.read(ROOT / 'code/main_5.ipynb', as_version=4)
    output_path = args.output.resolve()

    def report_progress(cell, cell_index):
        if cell.cell_type == 'code':
            print(f'Executing cell {cell_index + 1}/{len(notebook.cells)}', flush=True)

    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    with tempfile.TemporaryDirectory(prefix='raft-notebook-') as folder:
        work = Path(folder)
        kernel_dir = work / 'jupyter/kernels/raft-review'
        kernel_dir.mkdir(parents=True)
        (kernel_dir / 'kernel.json').write_text(json.dumps({
            'argv': [sys.executable, '-m', 'ipykernel_launcher', '-f', '{connection_file}'],
            'display_name': 'RAFT review', 'language': 'python',
        }), encoding='utf-8')
        environment = {
            'JUPYTER_PATH': str(work / 'jupyter'),
            'JUPYTER_RUNTIME_DIR': str(work / 'runtime'),
            'IPYTHONDIR': str(work / 'ipython'),
            'MPLCONFIGDIR': str(work / 'matplotlib'),
            'PYDEVD_DISABLE_FILE_VALIDATION': '1',
        }
        for value in list(environment.values())[:-1]:
            Path(value).mkdir(parents=True, exist_ok=True)
        previous = {key: os.environ.get(key) for key in environment}
        os.environ.update(environment)
        try:
            NotebookClient(
                notebook, timeout=args.timeout, kernel_name='raft-review', allow_errors=False,
                resources={'metadata': {'path': str(ROOT / 'code')}},
                on_cell_start=report_progress,
            ).execute()
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    # Retain portable kernel metadata; the temporary execution kernel is already closed.
    notebook.metadata['kernelspec'] = {
        'display_name': 'Python 3', 'language': 'python', 'name': 'python3',
    }
    images = verify_notebook(notebook)
    verify_inputs()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=output_path.parent, suffix='.ipynb.tmp', delete=False) as handle:
            temporary_path = Path(handle.name)
        nbformat.write(notebook, temporary_path)
        temporary_path.replace(output_path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()
    print(f'Saved {output_path.name}: {images} embedded figures; no execution errors.')


if __name__ == '__main__':
    main()
