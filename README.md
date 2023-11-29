# tg-approval-test-action

How to
```yaml
name: Node.js CI

on:
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Echo
        run: |
            echo "Hello World"

      - uses: powerdot/tg-approval-test-action@11
        timeout-minutes: 1
        with:
          TELEGRAM_KEY: '${{ secrets.TELEGRAM_KEY }}'
          TELEGRAM_CHAT_ID: '540443'

      - name: Echo2
        run: |
          echo "Hello World2"
```
