pub fn digest(bytes: &[u8]) -> [u8; 20] {
    let bit_len = (bytes.len() as u64).wrapping_mul(8);
    let blocks = (bytes.len() + 9).div_ceil(64);
    let mut state = [
        0x6745_2301u32,
        0xefcd_ab89,
        0x98ba_dcfe,
        0x1032_5476,
        0xc3d2_e1f0,
    ];
    for block in 0..blocks {
        let mut chunk = [0u8; 64];
        for (offset, byte) in chunk.iter_mut().enumerate() {
            let index = block * 64 + offset;
            *byte = if index < bytes.len() {
                bytes[index]
            } else if index == bytes.len() {
                0x80
            } else if index >= blocks * 64 - 8 {
                bit_len.to_be_bytes()[index - (blocks * 64 - 8)]
            } else {
                0
            };
        }
        compress(&mut state, &chunk);
    }
    let mut output = [0; 20];
    for (index, word) in state.into_iter().enumerate() {
        output[index * 4..index * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    output
}

fn compress(state: &mut [u32; 5], block: &[u8; 64]) {
    let mut words = [0u32; 80];
    for (index, word) in words.iter_mut().take(16).enumerate() {
        *word = u32::from_be_bytes(block[index * 4..index * 4 + 4].try_into().unwrap());
    }
    for index in 16..80 {
        words[index] =
            (words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16])
                .rotate_left(1);
    }
    let [mut a, mut b, mut c, mut d, mut e] = *state;
    for (index, &word) in words.iter().enumerate() {
        let (function, constant) = match index {
            0..=19 => ((b & c) | (!b & d), 0x5a82_7999),
            20..=39 => (b ^ c ^ d, 0x6ed9_eba1),
            40..=59 => ((b & c) | (b & d) | (c & d), 0x8f1b_bcdc),
            _ => (b ^ c ^ d, 0xca62_c1d6),
        };
        let next = a
            .rotate_left(5)
            .wrapping_add(function)
            .wrapping_add(e)
            .wrapping_add(constant)
            .wrapping_add(word);
        e = d;
        d = c;
        c = b.rotate_left(30);
        b = a;
        a = next;
    }
    for (value, addition) in state.iter_mut().zip([a, b, c, d, e]) {
        *value = value.wrapping_add(addition);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_known_vectors() {
        assert_eq!(
            digest(b"abc"),
            [
                0xa9, 0x99, 0x3e, 0x36, 0x47, 0x06, 0x81, 0x6a, 0xba, 0x3e, 0x25, 0x71, 0x78, 0x50,
                0xc2, 0x6c, 0x9c, 0xd0, 0xd8, 0x9d,
            ]
        );
        assert_eq!(
            digest(b""),
            [
                0xda, 0x39, 0xa3, 0xee, 0x5e, 0x6b, 0x4b, 0x0d, 0x32, 0x55, 0xbf, 0xef, 0x95, 0x60,
                0x18, 0x90, 0xaf, 0xd8, 0x07, 0x09,
            ]
        );
    }
}
