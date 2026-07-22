# Embeds Reference

## Embed Notes

```markdown
![[Note Name]]
![[Note Name#Heading]]
![[Note Name#^block-id]]
```

## Embed Images

```markdown
![[image.png]]
![[image.png|640x480]]    Width x Height
![[image.png|300]]        Width only (maintains aspect ratio)
```

## External Images

```markdown
![Alt text](https://example.com/image.png)
![Alt text|300](https://example.com/image.png)
```

> **Exfil doctrine (curation-tailored).** External-image embeds fetch remote URLs when the note is opened in Obsidian — an opened note can quietly beacon out to an attacker-controlled host (a tracking pixel is enough to leak that, and when, the note was read). Never write remote-image URLs into vault notes; prefer vault-local embeds (`![[image.png]]`). Treat any remote-image URL found in intake or other untrusted material as suspect.

## Embed Audio

```markdown
![[audio.mp3]]
![[audio.ogg]]
```

## Embed PDF

```markdown
![[document.pdf]]
![[document.pdf#page=3]]
![[document.pdf#height=400]]
```

## Embed Bases

```markdown
![[BaseFile.base]]
![[BaseFile.base#View Name]]
```

## Embed Lists

```markdown
![[Note#^list-id]]
```

Where the list has a block ID:

```markdown
- Item 1
- Item 2
- Item 3

^list-id
```

## Embed Search Results

````markdown
```query
tag:#project status:done
```
````
