"Set buttons/text to small/medium/big size"
"Set buttons/text to 1.6" (or whatever size)
"Pin Simon's chat" (or whatever chat)
"Mute Simon's chat" (or whatever chat)
"Set Simon's message bubbles to red" (whatever chat/color/or general bubbles)
Modify spacing between lines

Is there any other relevant option the assisant can't change?

"A bit bigger" should change a size by 0.1. The model can't tell it from plain "bigger" now: in training/source, prompts like "a bit bigger", "a little bigger" and "slightly larger" have no steps, the same as "bigger". Give them an explicit small step in training/source and in the steps description in assets/personalization_tools.json, retrain, then map it to 0.1 in ToolCallInterpreter._amount.

Enhance UI iOS and android

---

Activate the environment. You need to do this in every new terminal:
cd ~/development/fluffychat/training
source .venv/bin/activate

---

To remove everything when the project is finished:
rm -rf training/.venv training/.hf   # the environment, models and token
uv cache clean                        # uv's download cache
uv python uninstall 3.12              # the Python uv downloaded
brew uninstall uv