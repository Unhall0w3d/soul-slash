# Soul/ Missing LLM Intent Classifier Fix

This patch fixes:

```text
cannot load such file -- lib/soul_core/llm_intent_classifier
```

Cause:

`lib/soul_core/intent_router.rb` requires `llm_intent_classifier.rb`, but the file was not present in the working tree.

## Install

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_missing_llm_intent_classifier_fix_overlay.zip
```

## Verify

```bash
ruby -c lib/soul_core/llm_intent_classifier.rb
ruby -c lib/soul_core/intent_router.rb
ruby -c bin/soul

ruby bin/soul intent "run a file cleanup in Downloads"
```

Then retry the restore workflow test.
