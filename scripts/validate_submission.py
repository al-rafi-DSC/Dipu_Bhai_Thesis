"""Validate the input hashes and the saved, executed professor-review notebook."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import nbformat
import numpy as np
import pandas as pd

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


def verify_artifacts(root: Path = ROOT) -> int:
    """Check published exports, source identity and held-out scores independently."""
    metadata = json.loads((root / 'results/processing_metadata.json').read_text(encoding='utf-8'))
    for relative, expected in metadata['artifacts'].items():
        target = (root / relative).resolve()
        if not target.is_relative_to(root.resolve()):
            raise ValueError('Artifact path escapes repository.')
        if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Export hash mismatch: {relative}')
    for source_name, expected in metadata['source_hashes'].items():
        filename = {'RAFT export': 'merged_raft.csv', 'Weather export': 'merged_meteo.csv',
                    'Sky export': 'merged_ir.csv', 'Full merged table': 'merged_dataset_104957.csv'}[source_name]
        assert hashlib.sha256((root / 'processed' / filename).read_bytes()).hexdigest() == expected
    assert hashlib.sha256((root / 'references/PLOT_TRESCO_CORRELATIONS_ML-2.m').read_bytes()).hexdigest() == metadata['matlab_sha256']
    data = pd.read_csv(root / 'processed/final_processed_dataset.csv', parse_dates=['timestamp']).set_index('timestamp')
    assert list(data.columns) == ['Q_net', 'T_amb', 'RH', 'G', 'v', 'T_sky']
    assert len(data) == metadata['rows'] and np.isfinite(data.to_numpy()).all()
    assert data.index.is_unique and data.index.is_monotonic_increasing
    assert ((data.index-data.index.normalize()) % pd.Timedelta('3min') == pd.Timedelta(0)).all()
    audit = pd.read_csv(root / 'results/bin_audit.csv', parse_dates=['timestamp']).set_index('timestamp')
    pd.testing.assert_index_equal(audit.index[audit.retained], data.index)
    assert audit.loc[audit.retained, [c for c in audit if c.endswith('_native_count')]].ge(1).all().all()
    assert int((~audit.retained).sum()) == metadata['excluded_bins']
    excluded_prefix = np.r_[0, (~audit.retained).to_numpy().cumsum()]
    for variable in data.columns:
        starts = pd.to_datetime(audit.loc[audit.retained, variable + '_support_start'], format='mixed').dt.floor('3min')
        ends = pd.to_datetime(audit.loc[audit.retained, variable + '_support_end'], format='mixed').dt.floor('3min')
        left = audit.index.get_indexer(starts)
        right = audit.index.get_indexer(ends)
        assert (left >= 0).all() and (right >= left).all()
        assert (excluded_prefix[right+1]-excluded_prefix[left] == 0).all(), 'Smoothing crosses an excluded interval.'
    assignments = pd.read_csv(root / 'results/split_assignments.csv',
                              parse_dates=['timestamp']).set_index('timestamp')
    for column in ['source_start', 'source_end']:
        assignments[column] = pd.to_datetime(assignments[column], format='mixed')
    pd.testing.assert_index_equal(assignments.index, data.index)
    train = assignments['Chronological holdout'].eq('train')
    valid = assignments['Chronological holdout'].eq('validation')
    assert assignments.loc[train, 'source_end'].max() < assignments.loc[valid, 'source_start'].min()
    scores = pd.read_csv(root / 'results/metrics.csv')
    predictions = pd.read_csv(root / 'results/validation_predictions.csv', parse_dates=['timestamp'])
    for evaluation, group in predictions.groupby('evaluation'):
        group = group.set_index('timestamp')
        expected_index = assignments.index[assignments[evaluation].eq('validation')]
        pd.testing.assert_index_equal(group.index, expected_index)
        np.testing.assert_allclose(group.Measured, data.loc[group.index, 'Q_net'], rtol=1e-9, atol=1e-9)
        for model, column in [('Random Forest', 'Predicted'), ('Training-mean baseline', 'Training-mean baseline')]:
            error = group[column]-group.Measured
            row = scores.loc[scores.Evaluation.eq(evaluation) & scores.Model.eq(model) & scores.Partition.eq('Validation')].iloc[0]
            expected = [np.sqrt(np.mean(error**2)), np.mean(np.abs(error)),
                        1-np.sum(error**2)/np.sum((group.Measured-group.Measured.mean())**2)]
            np.testing.assert_allclose(row[['RMSE (W/m²)', 'MAE (W/m²)', 'R²']].astype(float), expected, rtol=1e-8, atol=1e-8)
            assert int(row.N) == len(group)
    return len(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notebook', type=Path, default=ROOT / 'code/main.ipynb')
    args = parser.parse_args()
    manifest = verify_inputs()
    notebook = nbformat.read(args.notebook, as_version=4)
    images = verify_notebook(notebook)
    rows = verify_artifacts()
    print(f"Verified {len(manifest['files'])} unchanged input files.")
    print(f'Notebook valid: all code cells executed, no saved errors, {images} embedded figures.')
    print(f'Exports valid: {rows:,} rows; hashes, source support and held-out scores verified.')


if __name__ == '__main__':
    main()
