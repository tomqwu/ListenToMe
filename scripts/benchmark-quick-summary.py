#!/usr/bin/env python3
"""Benchmark the shipping evaluator prompt against live catalog Flash models and an optional Apple runner.
Synthetic inputs only. Credentials are read from the existing macOS Keychain into memory, never emitted.
Usage: python3 scripts/benchmark-quick-summary.py --output dist/benchmark --repeats 3 [--apple-runner PATH]
"""
import argparse
import json
import pathlib
import statistics
import subprocess
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]


def parse_response(text):
    answer = text.strip()
    if answer.endswith('```'):
        answer = answer[:-3].strip()
    for start in [i for i, c in enumerate(answer) if c == '{'][-64:][::-1]:
        try:
            value = json.loads(answer[start:])
            if set(value) != {'action', 'context', 'bullets', 'reviews'}:
                continue
            assert value['action'] in ('keep', 'publish')
            assert isinstance(value['context'], str) and len(value['context']) <= 2000
            bullets = value['bullets']
            assert isinstance(bullets, list) and len(bullets) <= 5
            assert all(isinstance(b, str) and b.strip() and '\n' not in b for b in bullets)
            assert len(''.join(bullets)) <= 1500
            assert (not bullets) if value['action'] == 'keep' else bool(bullets)
            reviews = value['reviews']
            assert isinstance(reviews, list) and len(reviews) <= 2
            assert len({r['mode'] for r in reviews}) == len(reviews)
            for review in reviews:
                assert review['mode'] in ('summary', 'deep')
                assert review['confidence'] in ('low', 'medium', 'high')
                assert isinstance(review['reason'], str) and 0 < len(review['reason'].strip()) <= 160
            return value
        except (ValueError, TypeError, KeyError, AssertionError):
            continue
    return None


def payload(case):
    change = {'id': 's1' if case.get('previous') else 's2', 'text': case['speech']}
    if case.get('previous'):
        change['previousText'] = case['previous']
    return {'runningContext': case['context'], 'visibleSummary': case['summary'],
            'recentSpeech': [], 'changes': [change], 'reviewsCompleted': [], 'pendingReviews': []}


def score(case, evaluation):
    if evaluation is None:
        return {'action': False, 'facts': False, 'review': False, 'all': False}
    visible = '\n'.join(evaluation['bullets']) if evaluation['action'] == 'publish' else case['summary']
    action = evaluation['action'] == case['expected']
    facts = all(t.lower() in visible.lower() for t in case['contains']) and not any(
        t.lower() in visible.lower() for t in case['excludes'])
    review = case['review'] is None or any(r['mode'] == case['review'] for r in evaluation['reviews'])
    return {'action': action, 'facts': facts, 'review': review, 'all': action and facts and review}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--apple-runner', type=pathlib.Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    key = subprocess.run(['security', 'find-generic-password', '-s', 'com.tomwu.ListenToMe', '-a', 'ollama', '-w'],
                         capture_output=True, check=True).stdout.decode().strip()
    request = urllib.request.Request('https://ollama.com/api/tags', headers={'Authorization': 'Bearer ' + key})
    with urllib.request.urlopen(request, timeout=15) as response:
        catalog = json.load(response)
    flash = [m for m in catalog['models'] if 'flash' in m['name'].lower()]
    # Latest API-modified Flash variant per family, matching the app's catalog convention.
    from datetime import datetime
    latest = {}
    for model in flash:
        family = model['name'].split('-')[0]
        if family not in latest or datetime.fromisoformat(model['modified_at'].replace('Z', '+00:00')) > datetime.fromisoformat(
                latest[family]['modified_at'].replace('Z', '+00:00')):
            latest[family] = model
    models = [m['name'] for m in latest.values()]
    (args.output / 'catalog.json').write_text(json.dumps(flash, indent=2))
    prompt = (ROOT / 'Sources/ListenToMeCore/QuickSummaryContext.swift').read_text().split('static let instructions = """')[1].split('"""')[0].strip()
    (args.output / 'prompt.txt').write_text(prompt)
    cases = json.loads((ROOT / 'scripts/fixtures/quick-evaluator-cases.json').read_text())
    records = []

    def cloud(model, case, repetition):
        data = {'model': model, 'stream': True, 'think': False, 'options': {'temperature': 0, 'num_predict': 1600},
                'messages': [{'role': 'system', 'content': prompt},
                             {'role': 'user', 'content': json.dumps(payload(case), ensure_ascii=False)}]}
        request = urllib.request.Request('https://ollama.com/api/chat', data=json.dumps(data).encode(),
            headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        started = time.monotonic(); text = ''; complete = False; error = None; first = None
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                for line in response:
                    if time.monotonic() - started >= 15:
                        error = '15-second application deadline'; break
                    obj = json.loads(line)
                    delta = obj.get('message', {}).get('content', '')
                    if delta and first is None:
                        first = time.monotonic() - started
                    text += delta
                    if len(text.encode()) > 16384:
                        error = 'response size limit'; break
                    if obj.get('done'):
                        complete = True; break
        except Exception as exc:
            error = type(exc).__name__
        elapsed = time.monotonic() - started
        evaluation = parse_response(text) if complete else None
        return {'model': model, 'case': case['id'], 'repetition': repetition, 'seconds': elapsed,
                'first_content_seconds': first, 'complete': complete, 'schema_valid': evaluation is not None,
                'evaluation': evaluation, 'error': error, 'response_bytes': len(text.encode()), 'checks': score(case, evaluation)}

    # Alternate cloud models for every case; only one request at a time avoids shared-account contention.
    for repetition in range(args.repeats):
        for case in cases:
            for model in (models if repetition % 2 == 0 else list(reversed(models))):
                result = cloud(model, case, repetition)
                records.append(result)
                (args.output / 'results.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
                print(json.dumps({k: result[k] for k in ('model', 'case', 'seconds', 'schema_valid', 'checks')}), flush=True)
    if args.apple_runner:
        for repetition in range(args.repeats):
            for case in cases:
                started = time.monotonic()
                try:
                    run = subprocess.run([str(args.apple_runner.resolve())], input=json.dumps({'system': prompt, 'input': payload(case)}),
                                         text=True, capture_output=True, timeout=20, check=True)
                    result = json.loads(run.stdout)
                    evaluation = parse_response(result.get('response', ''))
                    row = {'model': 'Apple Intelligence (this Mac)', 'case': case['id'], 'repetition': repetition,
                           'seconds': result['seconds'], 'schema_valid': evaluation is not None,
                           'evaluation': evaluation, 'error': result.get('error'), 'checks': score(case, evaluation)}
                except Exception as exc:
                    row = {'model': 'Apple Intelligence (this Mac)', 'case': case['id'], 'repetition': repetition,
                           'seconds': time.monotonic()-started, 'schema_valid': False, 'error': type(exc).__name__,
                           'evaluation': None, 'checks': score(case, None)}
                records.append(row)
                (args.output / 'results.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
                print(json.dumps({k: row[k] for k in ('model', 'case', 'seconds', 'schema_valid', 'checks')}), flush=True)
    summary = []
    for model in dict.fromkeys(r['model'] for r in records):
        rows = [r for r in records if r['model'] == model]
        successful = [r['seconds'] for r in rows if r['schema_valid']]
        summary.append({'model': model, 'requests': len(rows), 'schema_valid': sum(r['schema_valid'] for r in rows),
                        'all_checks_passed': sum(r['checks']['all'] for r in rows),
                        'median_success_seconds': statistics.median(successful) if successful else None,
                        'slowest_success_seconds': max(successful) if successful else None,
                        'over_five_seconds': sum(r['seconds'] > 5 for r in rows)})
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
