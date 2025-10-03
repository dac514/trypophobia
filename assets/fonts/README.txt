Source file: https://fonts.google.com/noto/specimen/Noto+Color+Emoji
Problem: NotoColorEmoji-Regular.ttf is too big.
Solution: Create a subset with only the emojis (and variants) we want: 👾 💣 👁️

pipx install fonttools
pipx inject fonttools lxml
pyftsubset NotoColorEmoji-Regular.ttf --unicodes=U+1F47E,U+1F4A3,U+1F441,U+FE0E,U+FE0F

After generating, verify the new NotoColorEmoji-Regular.subset.ttf font with https://wakamaifondue.com/
