import copy
from pathlib import Path
import textwrap
import unittest


class CatalogWorkflowRunIdentity(unittest.TestCase):
    def setUp(self):
        workflow = Path(__file__).resolve().parents[2] / '.github/workflows/catalog-check-publish.yml'
        code = textwrap.dedent(workflow.read_text(encoding='utf-8').split("          python3 - <<'PY'\n", 1)[1])
        start = code.index("\n", code.index("main_sha = api(")) + 1
        self.validation = code[start:code.index("pull_path =", start)]
        self.main = 'c9b160cc22416750bc2c79ccf04ea899287c4320'
        self.head = 'e7dbf67684db542c40458d95c369076081f248bf'
        self.run = {'head_sha': self.head, 'pull_requests': [
            {'number': 1, 'base': {'sha': self.main}, 'head': {'sha': self.head}}
        ]}

    def validate(self, run):
        exec(self.validation, {'run': run, 'main_sha': self.main, 'head_sha': self.head, 'pull_number': 1})

    def test_pr_head_and_current_base_are_accepted(self):
        self.validate(self.run)

    def test_changed_base_is_rejected(self):
        run = copy.deepcopy(self.run)
        run['pull_requests'][0]['base']['sha'] = '0' * 40
        with self.assertRaises(ValueError):
            self.validate(run)

    def test_changed_head_is_rejected(self):
        run = copy.deepcopy(self.run)
        run['head_sha'] = self.main
        with self.assertRaises(ValueError):
            self.validate(run)

    def test_missing_pull_identity_is_rejected(self):
        run = {'head_sha': self.head, 'pull_requests': []}
        with self.assertRaises(ValueError):
            self.validate(run)

    def test_ambiguous_pull_identity_is_rejected(self):
        run = copy.deepcopy(self.run)
        run['pull_requests'].append(copy.deepcopy(run['pull_requests'][0]))
        with self.assertRaises(ValueError):
            self.validate(run)

    def test_pull_snapshot_head_must_match_the_run(self):
        run = copy.deepcopy(self.run)
        run['pull_requests'][0]['head']['sha'] = '0' * 40
        with self.assertRaises(ValueError):
            self.validate(run)

    def test_another_pull_is_rejected(self):
        run = copy.deepcopy(self.run)
        run['pull_requests'][0]['number'] = 2
        with self.assertRaises(ValueError):
            self.validate(run)


if __name__ == '__main__':
    unittest.main()
