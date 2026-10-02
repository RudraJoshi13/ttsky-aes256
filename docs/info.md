<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project puts the open-source AES core by Joachim Strömbergson
([secworks/aes](https://github.com/secworks/aes), BSD-2-Clause) on Tiny Tapeout, without changes to the core.
It implements AES as specified in NIST FIPS-197 with 128-bit and 256-bit keys, for both encryption and
decryption. The core processes one 128-bit block at a time with a 32-bit wide round datapath (4 S-boxes shared
with the key expansion), and stores all expanded round keys in registers.

Tiny Tapeout only has 24 I/O pins, so a small wrapper turns the core's 32-bit register interface into a byte
interface:

| Pins | Function |
|------|----------|
| `ui[4:0]` | word index (register select) |
| `ui[6:5]` | byte within the word (0 = bits 7:0, 3 = bits 31:24) |
| `ui[7]` | write strobe, active high (synchronised inside the chip) |
| `uio[7:0]` | write data byte (all `uio` pins are inputs) |
| `uo[7:0]` | read data byte of the selected word and byte |

Bytes 0 to 2 of a word are held in a staging register. Writing byte 3 writes the whole 32-bit word into the
core, so always write bytes 0, 1, 2 and then 3.

| Word index | Register | Notes |
|-----------|----------|-------|
| 0, 1 | NAME0, NAME1 | reads "aes " and "    " |
| 2 | VERSION | reads "0.60" |
| 3 | CTRL | bit 0 init (key expansion), bit 1 next (process block) |
| 4 | STATUS | bit 0 ready, bit 1 valid |
| 5 | CONFIG | bit 0 encdec (1 = encrypt, 0 = decrypt), bit 1 keylen (1 = 256-bit) |
| 8 to 15 | KEY0 to KEY7 | KEY0 is the most significant word; a 128-bit key goes in KEY0 to KEY3 |
| 16 to 19 | BLOCK0 to BLOCK3 | BLOCK0 is the most significant word |
| 20 to 23 | RESULT0 to RESULT3 | RESULT0 is the most significant word |

## How to test

1. Reset the chip.
2. Write the key to KEY0 to KEY7.
3. Write CONFIG with the key length bit (`0x2` for AES-256, `0x0` for AES-128).
4. Write `0x1` to CTRL to start the key expansion, then poll STATUS until bit 0 (ready) is 1.
5. Write the block to BLOCK0 to BLOCK3.
6. Write CONFIG again with the key length and the direction (`0x3` for AES-256 encryption).
7. Write `0x2` to CTRL, then poll STATUS until bit 1 (valid) is 1.
8. Read RESULT0 to RESULT3.

For each byte write: set `ui[6:0]` and `uio[7:0]`, raise `ui[7]`, hold it for at least 3 clock cycles, then
lower it. For each read: set `ui[6:0]` and read `uo[7:0]` 2 or more clock cycles later.

Example (NIST FIPS-197 Appendix C.3): key `000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`,
plaintext `00112233445566778899aabbccddeeff`, ciphertext `8ea2b7ca516745bfeafc49904b496089`.

## External hardware

None. The RP2040 on the Tiny Tapeout demo board can drive `ui` and `uio` and read `uo`.
