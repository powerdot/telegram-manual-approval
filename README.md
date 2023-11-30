# Telegram Manual Approval

[@viz-A-viz](https://github.com/viz-A-viz) 🤜🤛 [@powerdot](https://github.com/powerdot)

![Concept](about.png)

Obtain manual approval for GitHub Actions workflows through Telegram messages. This action pauses a workflow and requires a manual response via Telegram to continue.

This action is particularly useful for deployment workflows where you want an extra layer of control before proceeding with sensitive operations like production deployment.

## How it works

1. When the workflow reaches the `telegram-manual-approval` step, it sends a customisable message containing approval and rejection buttons to a specified Telegram chat.
2. A user with appropriate permissions can click on the approval or rejection button within Telegram to continue or halt the workflow.
3. On approval, the workflow proceeds, and on rejection, the workflow fails and stops.

## Usage

To use this action, add the following step to your GitHub Actions workflow:

```yaml
steps:
  - uses: powerdot/telegram-manual-approval@main
    with:
      TELEGRAM_KEY: ${{ secrets.TELEGRAM_KEY }}
      TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
      APPROVAL_TEXT: 'Please approve deployment:'
      APPROVAL_BUTTON: 'Approve'
      REJECT_BUTTON: 'Reject'
      APPROVED_TEXT: 'Approved!'
      REJECTED_TEXT: 'Rejected!'
      TIMEOUT_TEXT: 'Timeout!'
```

Configure the inputs to customize the Telegram message:
- `TELEGRAM_KEY`: Your Telegram Bot key. (*This should be stored securely in your repository secrets*)
- `TELEGRAM_CHAT_ID`: The Telegram chat ID where approval requests will be sent.
- `APPROVAL_TEXT`: Custom message text prompting for approval.
- `APPROVAL_BUTTON`: Text for the approval button.
- `REJECT_BUTTON`: Text for the rejection button.
- `APPROVED_TEXT`: Message to indicate successful approval.
- `REJECTED_TEXT`: Message to indicate successful rejection.
- `TIMEOUT_TEXT`: Message to indicate a timeout if no response is received.

You can also set a timeout limit for the approval step using `timeout-minutes` in your workflow file:

```yaml
steps:
  - uses: powerdot/telegram-manual-approval@main
    timeout-minutes: 10
    with:
      ...
```

*Note: The default value for `UPDATE_REQUESTS` is 60, which corresponds to a one-minute timeout waiting for a response. Adjust this value according to your preference.*

### Permissions

Ensure that the GitHub token used by the action has permissions to send messages via Telegram Bot API. You may not need to set any special permissions in your GitHub workflow for this action unless your workflow requires additional steps that interact with the GitHub environment.

## Limitations

- The maximum wait time for an approval is determined by the `timeout-minutes` you set for the step. Please ensure that this duration is reasonable to allow adequate time for manual approval.
- Similar to other workflow steps, if the manual approval step times out, the workflow run will fail.
- To protect your Telegram Bot API key, always use GitHub repository secrets to store it instead of hardcoding it in your workflow files.

## Development and Contribution

If you're interested in contributing to the development of this GitHub Action, please refer to the `CONTRIBUTING.md` file in this repository for more details on how you can contribute.

We welcome contributions and improvements from the community!

---
This GitHub Action is provided "as is" with no warranty. Usage of this action is at your own risk. For complete instructions on how to create and configure Telegram bots, please refer to the [official Telegram Bot documentation](https://core.telegram.org/bots).

For support and contributions, feel free to open an issue or a pull request in the [repository](https://github.com/powerdot/telegram-manual-approval).

Good luck with automating your workflows!

---

*(Note: Consider adjusting the example and the variable names to match the specifics of your actual GitHub Action implementation. The example above presumes that you've defined the inputs in your `action.yml` and have a corresponding `main.sh` script that will handle the Telegram interactions.)*
