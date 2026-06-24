import { describe, it } from 'node:test';
import assert from 'node:assert';
import { BotDifficulty, BotDifficultyConfig } from '../services/BotDifficulty';

describe('BotDifficulty', () => {
  describe('static difficulty configs', () => {
    it('bronze has correct values', () => {
      const bronze = BotDifficulty.bronze;

      assert.strictEqual(bronze.name, 'Bronze');
      assert.strictEqual(bronze.forgetChancePerTurn, 0.18);
      assert.strictEqual(bronze.confusionOnSwap, 0.30);
      assert.strictEqual(bronze.dutchThreshold, 10);
      assert.strictEqual(bronze.reactionSpeed, 0.55);
      assert.strictEqual(bronze.matchAccuracy, 0.75);
      assert.strictEqual(bronze.reactionMatchChance, 0.35);
    });

    it('silver has correct values', () => {
      const silver = BotDifficulty.silver;

      assert.strictEqual(silver.name, 'Argent');
      assert.strictEqual(silver.forgetChancePerTurn, 0.08);
      assert.strictEqual(silver.confusionOnSwap, 0.12);
      assert.strictEqual(silver.dutchThreshold, 6);
      assert.strictEqual(silver.reactionSpeed, 0.75);
      assert.strictEqual(silver.matchAccuracy, 0.85);
      assert.strictEqual(silver.reactionMatchChance, 0.55);
    });

    it('difficult has the strongest values (fusion ex-Or+Platine = Platine)', () => {
      const difficult = BotDifficulty.difficult;

      assert.strictEqual(difficult.name, 'Difficile');
      assert.strictEqual(difficult.forgetChancePerTurn, 0.0);
      assert.strictEqual(difficult.confusionOnSwap, 0.0);
      assert.strictEqual(difficult.dutchThreshold, 1);
      assert.strictEqual(difficult.reactionSpeed, 1.0);
      assert.strictEqual(difficult.matchAccuracy, 1.0);
      assert.strictEqual(difficult.reactionMatchChance, 1.0);
    });
  });

  describe('fromMMR', () => {
    it('returns bronze for MMR < 300', () => {
      assert.strictEqual(BotDifficulty.fromMMR(0).name, 'Bronze');
      assert.strictEqual(BotDifficulty.fromMMR(100).name, 'Bronze');
      assert.strictEqual(BotDifficulty.fromMMR(299).name, 'Bronze');
    });

    it('returns silver for MMR 300-599', () => {
      assert.strictEqual(BotDifficulty.fromMMR(300).name, 'Argent');
      assert.strictEqual(BotDifficulty.fromMMR(450).name, 'Argent');
      assert.strictEqual(BotDifficulty.fromMMR(599).name, 'Argent');
    });

    it('returns difficile for MMR >= 600 (ex Or 600-899 + Platine >=900 fusionnés)', () => {
      assert.strictEqual(BotDifficulty.fromMMR(600).name, 'Difficile');
      assert.strictEqual(BotDifficulty.fromMMR(750).name, 'Difficile');
      assert.strictEqual(BotDifficulty.fromMMR(900).name, 'Difficile');
      assert.strictEqual(BotDifficulty.fromMMR(2000).name, 'Difficile');
    });
  });

  describe('fromRank', () => {
    it('returns correct difficulty for Bronze rank', () => {
      assert.strictEqual(BotDifficulty.fromRank('Bronze').name, 'Bronze');
    });

    it('returns correct difficulty for Argent rank', () => {
      assert.strictEqual(BotDifficulty.fromRank('Argent').name, 'Argent');
    });

    it('returns difficile for legacy Or/Platine ranks + Difficile', () => {
      assert.strictEqual(BotDifficulty.fromRank('Or').name, 'Difficile');
      assert.strictEqual(BotDifficulty.fromRank('Platine').name, 'Difficile');
      assert.strictEqual(BotDifficulty.fromRank('Difficile').name, 'Difficile');
    });

    it('returns silver as default for unknown rank', () => {
      assert.strictEqual(BotDifficulty.fromRank('Unknown').name, 'Argent');
      assert.strictEqual(BotDifficulty.fromRank('').name, 'Argent');
    });
  });

  describe('difficulty progression', () => {
    it('has increasing difficulty properties', () => {
      const levels = [
        BotDifficulty.bronze,
        BotDifficulty.silver,
        BotDifficulty.difficult,
      ];

      // forgetChancePerTurn should decrease (lower = better memory)
      for (let i = 1; i < levels.length; i++) {
        assert.ok(
          levels[i].forgetChancePerTurn <= levels[i - 1].forgetChancePerTurn,
          `forgetChancePerTurn should decrease: ${levels[i].name} vs ${levels[i - 1].name}`
        );
      }

      // confusionOnSwap should decrease (lower = less mistakes)
      for (let i = 1; i < levels.length; i++) {
        assert.ok(
          levels[i].confusionOnSwap <= levels[i - 1].confusionOnSwap,
          `confusionOnSwap should decrease: ${levels[i].name} vs ${levels[i - 1].name}`
        );
      }

      // dutchThreshold should decrease (lower = more aggressive Dutch calls)
      for (let i = 1; i < levels.length; i++) {
        assert.ok(
          levels[i].dutchThreshold <= levels[i - 1].dutchThreshold,
          `dutchThreshold should decrease: ${levels[i].name} vs ${levels[i - 1].name}`
        );
      }

      // reactionSpeed should increase (higher = faster)
      for (let i = 1; i < levels.length; i++) {
        assert.ok(
          levels[i].reactionSpeed >= levels[i - 1].reactionSpeed,
          `reactionSpeed should increase: ${levels[i].name} vs ${levels[i - 1].name}`
        );
      }

      // matchAccuracy should increase (higher = more accurate)
      for (let i = 1; i < levels.length; i++) {
        assert.ok(
          levels[i].matchAccuracy >= levels[i - 1].matchAccuracy,
          `matchAccuracy should increase: ${levels[i].name} vs ${levels[i - 1].name}`
        );
      }

      // reactionMatchChance should increase (higher = more likely to match)
      for (let i = 1; i < levels.length; i++) {
        assert.ok(
          levels[i].reactionMatchChance >= levels[i - 1].reactionMatchChance,
          `reactionMatchChance should increase: ${levels[i].name} vs ${levels[i - 1].name}`
        );
      }

    });
  });
});
