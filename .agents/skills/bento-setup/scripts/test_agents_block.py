import unittest

from agents_block import apply, build_block


class ApplyTest(unittest.TestCase):
    def test_added_updated_unchanged(self):
        block = build_block()
        text, action = apply("# repo\n", block)
        self.assertEqual(action, "added")
        self.assertEqual(text, "# repo\n\n" + block + "\n")
        self.assertEqual(apply(text, block), (text, "unchanged"))
        stale = text.replace(block, "<!-- bento:start -->\nold\n<!-- bento:end -->")
        self.assertEqual(apply(stale, block), (text, "updated"))


if __name__ == "__main__":
    unittest.main()
