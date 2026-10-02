# SPDX-FileCopyrightText: © 2026 Rudra Joshi
# SPDX-License-Identifier: Apache-2.0
#
# cocotb tests for tt_um_rj_aes using NIST FIPS-197 Appendix C and
# NIST SP 800-38A ECB vectors.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Word indices (see src/project.v)
W_NAME0, W_NAME1, W_VERSION = 0, 1, 2
W_CTRL, W_STATUS, W_CONFIG = 3, 4, 5
W_KEY, W_BLOCK, W_RESULT = 8, 16, 20

STROBE = 0x80


async def write_word(dut, word, value):
    """Write a 32-bit word, byte 0 first, byte 3 last (byte 3 commits)."""
    for b in range(4):
        addr = (b << 5) | word
        dut.uio_in.value = (value >> (8 * b)) & 0xFF
        dut.ui_in.value = addr
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = STROBE | addr
        await ClockCycles(dut.clk, 4)
        dut.ui_in.value = addr
        await ClockCycles(dut.clk, 2)


async def read_word(dut, word):
    value = 0
    for b in range(4):
        dut.ui_in.value = (b << 5) | word
        await ClockCycles(dut.clk, 3)
        value |= dut.uo_out.value.to_unsigned() << (8 * b)
    return value


async def wait_status(dut, bit, timeout=2000):
    for _ in range(timeout):
        if (await read_word(dut, W_STATUS)) >> bit & 1:
            return
    raise AssertionError(f"timeout waiting for STATUS bit {bit}")


async def load_key(dut, key, keylen256):
    """key is a 256-bit int; for AES-128 the key sits in the upper 128 bits."""
    for i in range(8):
        await write_word(dut, W_KEY + i, (key >> (32 * (7 - i))) & 0xFFFFFFFF)
    await write_word(dut, W_CONFIG, (keylen256 << 1))
    await write_word(dut, W_CTRL, 0x1)  # init: key expansion
    await wait_status(dut, 0)           # ready


async def process_block(dut, block, encrypt, keylen256):
    for i in range(4):
        await write_word(dut, W_BLOCK + i, (block >> (32 * (3 - i))) & 0xFFFFFFFF)
    await write_word(dut, W_CONFIG, (keylen256 << 1) | encrypt)
    await write_word(dut, W_CTRL, 0x2)  # next: process block
    await wait_status(dut, 1)           # valid
    result = 0
    for i in range(4):
        result = (result << 32) | await read_word(dut, W_RESULT + i)
    return result


async def reset(dut):
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_core_name(dut):
    await reset(dut)
    assert await read_word(dut, W_NAME0) == 0x61657320  # "aes "
    assert await read_word(dut, W_NAME1) == 0x20202020
    assert await read_word(dut, W_VERSION) == 0x302E3630  # "0.60"
    assert dut.uio_oe.value.to_unsigned() == 0


VECTORS = [
    # (name, key (256-bit field), keylen256, plaintext, ciphertext)
    ("FIPS-197 C.1 AES-128",
     0x000102030405060708090A0B0C0D0E0F << 128, 0,
     0x00112233445566778899AABBCCDDEEFF, 0x69C4E0D86A7B0430D8CDB78070B4C55A),
    ("FIPS-197 C.3 AES-256",
     0x000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F, 1,
     0x00112233445566778899AABBCCDDEEFF, 0x8EA2B7CA516745BFEAFC49904B496089),
    ("SP800-38A F.1.5 AES-256 ECB block 1",
     0x603DEB1015CA71BE2B73AEF0857D77811F352C073B6108D72D9810A30914DFF4, 1,
     0x6BC1BEE22E409F96E93D7E117393172A, 0xF3EED1BDB5D2A03C064B5A7E3DB181F8),
    ("SP800-38A F.1.1 AES-128 ECB block 1",
     0x2B7E151628AED2A6ABF7158809CF4F3C << 128, 0,
     0x6BC1BEE22E409F96E93D7E117393172A, 0x3AD77BB40D7A3660A89ECAF32466EF97),
]


@cocotb.test()
async def test_nist_encrypt_decrypt(dut):
    await reset(dut)
    for name, key, k256, pt, ct in VECTORS:
        await load_key(dut, key, k256)
        got_ct = await process_block(dut, pt, encrypt=1, keylen256=k256)
        dut._log.info(f"{name}: encrypt -> {got_ct:032x}")
        assert got_ct == ct, f"{name} encrypt: expected {ct:032x}, got {got_ct:032x}"
        got_pt = await process_block(dut, ct, encrypt=0, keylen256=k256)
        dut._log.info(f"{name}: decrypt -> {got_pt:032x}")
        assert got_pt == pt, f"{name} decrypt: expected {pt:032x}, got {got_pt:032x}"
