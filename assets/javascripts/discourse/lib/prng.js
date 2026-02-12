/* eslint-disable no-bitwise */
/* global BigInt */
// Simple deterministic PRNG implementation
// Bitwise operations are essential for the PRNG algorithm
export class SeededRandom {
  constructor(seed) {
    // Initialize state from seed
    this.state = 0n;
    for (let i = 0; i < seed.length; i++) {
      this.state =
        (this.state * 31n + BigInt(seed.charCodeAt(i))) & 0xffffffffffffffffn;
    }
    // Ensure state is not zero
    if (this.state === 0n) {
      this.state = 1n;
    }
  }

  // Generate next random number in [0,1) range
  next() {
    // Simple but effective algorithm: xorshift64*
    this.state ^= this.state >> 12n;
    this.state ^= this.state << 25n;
    this.state ^= this.state >> 27n;
    this.state *= 2685821657736338717n;
    this.state &= 0xffffffffffffffffn;

    // Convert to [0,1) range
    return Number(this.state) / Number(0x10000000000000000n);
  }

  // Python's random.choice() equivalent
  choice(array) {
    if (!array || array.length === 0) {
      return undefined;
    }
    const r = this.next();
    const index = Math.floor(r * array.length);
    return array[index];
  }
}
