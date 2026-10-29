#!/usr/bin/env bash
# Run only on explicit operator launch. Keeps a normal user shell on the same PTY.
set -u
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
case "${1-}" in
  --open-approved-trial)
    exec konsole --separate -p 'tabtitle=SOUL ROSTER INTERFACE TRIAL - sudo' -e bash "$script_dir/roster-test-console.sh" --run-approved-trial
    ;;
  --run-approved-trial)
    printf '%s\n' 'GPT-OSS + Gemma only; 44-minute maximum, 40 replies maximum.' 'Enter sudo locally. Models run unprivileged; no automatic retry.'
    if sudo -v; then
      /home/bhones/.rbenv/versions/4.0.7/bin/ruby "$script_dir/run-roster-interface-trial.rb" --approved-roster-interface-trial
      result=$?
    else
      result=1
    fi
    printf '\nTrial exit status: %s. No retry started. Returning to an ordinary user shell.\n' "$result"
    exec bash --noprofile --norc -i
    ;;
  *) printf '%s\n' 'Expected --open-approved-trial or --run-approved-trial; nothing started.' >&2; exit 2 ;;
esac
