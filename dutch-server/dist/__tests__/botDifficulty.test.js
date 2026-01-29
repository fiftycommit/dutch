"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const BotDifficulty_1 = require("../services/BotDifficulty");
(0, node_test_1.describe)('BotDifficulty', () => {
    (0, node_test_1.describe)('static difficulty configs', () => {
        (0, node_test_1.it)('bronze has correct values', () => {
            const bronze = BotDifficulty_1.BotDifficulty.bronze;
            node_assert_1.default.strictEqual(bronze.name, 'Bronze');
            node_assert_1.default.strictEqual(bronze.forgetChancePerTurn, 0.18);
            node_assert_1.default.strictEqual(bronze.confusionOnSwap, 0.30);
            node_assert_1.default.strictEqual(bronze.dutchThreshold, 10);
            node_assert_1.default.strictEqual(bronze.reactionSpeed, 0.55);
            node_assert_1.default.strictEqual(bronze.matchAccuracy, 0.75);
            node_assert_1.default.strictEqual(bronze.reactionMatchChance, 0.35);
            node_assert_1.default.strictEqual(bronze.keepCardThreshold, 7);
        });
        (0, node_test_1.it)('silver has correct values', () => {
            const silver = BotDifficulty_1.BotDifficulty.silver;
            node_assert_1.default.strictEqual(silver.name, 'Argent');
            node_assert_1.default.strictEqual(silver.forgetChancePerTurn, 0.08);
            node_assert_1.default.strictEqual(silver.confusionOnSwap, 0.12);
            node_assert_1.default.strictEqual(silver.dutchThreshold, 6);
            node_assert_1.default.strictEqual(silver.reactionSpeed, 0.75);
            node_assert_1.default.strictEqual(silver.matchAccuracy, 0.85);
            node_assert_1.default.strictEqual(silver.reactionMatchChance, 0.55);
            node_assert_1.default.strictEqual(silver.keepCardThreshold, 6);
        });
        (0, node_test_1.it)('gold has correct values', () => {
            const gold = BotDifficulty_1.BotDifficulty.gold;
            node_assert_1.default.strictEqual(gold.name, 'Or');
            node_assert_1.default.strictEqual(gold.forgetChancePerTurn, 0.01);
            node_assert_1.default.strictEqual(gold.confusionOnSwap, 0.01);
            node_assert_1.default.strictEqual(gold.dutchThreshold, 3);
            node_assert_1.default.strictEqual(gold.reactionSpeed, 0.96);
            node_assert_1.default.strictEqual(gold.matchAccuracy, 0.97);
            node_assert_1.default.strictEqual(gold.reactionMatchChance, 0.9);
            node_assert_1.default.strictEqual(gold.keepCardThreshold, 3);
        });
        (0, node_test_1.it)('platinum has perfect values', () => {
            const platinum = BotDifficulty_1.BotDifficulty.platinum;
            node_assert_1.default.strictEqual(platinum.name, 'Platine');
            node_assert_1.default.strictEqual(platinum.forgetChancePerTurn, 0.0);
            node_assert_1.default.strictEqual(platinum.confusionOnSwap, 0.0);
            node_assert_1.default.strictEqual(platinum.dutchThreshold, 1);
            node_assert_1.default.strictEqual(platinum.reactionSpeed, 1.0);
            node_assert_1.default.strictEqual(platinum.matchAccuracy, 1.0);
            node_assert_1.default.strictEqual(platinum.reactionMatchChance, 1.0);
            node_assert_1.default.strictEqual(platinum.keepCardThreshold, 1);
        });
    });
    (0, node_test_1.describe)('fromMMR', () => {
        (0, node_test_1.it)('returns bronze for MMR < 300', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(0).name, 'Bronze');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(100).name, 'Bronze');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(299).name, 'Bronze');
        });
        (0, node_test_1.it)('returns silver for MMR 300-599', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(300).name, 'Argent');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(450).name, 'Argent');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(599).name, 'Argent');
        });
        (0, node_test_1.it)('returns gold for MMR 600-899', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(600).name, 'Or');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(750).name, 'Or');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(899).name, 'Or');
        });
        (0, node_test_1.it)('returns platinum for MMR >= 900', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(900).name, 'Platine');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(1000).name, 'Platine');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromMMR(2000).name, 'Platine');
        });
    });
    (0, node_test_1.describe)('fromRank', () => {
        (0, node_test_1.it)('returns correct difficulty for Bronze rank', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromRank('Bronze').name, 'Bronze');
        });
        (0, node_test_1.it)('returns correct difficulty for Argent rank', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromRank('Argent').name, 'Argent');
        });
        (0, node_test_1.it)('returns correct difficulty for Or rank', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromRank('Or').name, 'Or');
        });
        (0, node_test_1.it)('returns correct difficulty for Platine rank', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromRank('Platine').name, 'Platine');
        });
        (0, node_test_1.it)('returns silver as default for unknown rank', () => {
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromRank('Unknown').name, 'Argent');
            node_assert_1.default.strictEqual(BotDifficulty_1.BotDifficulty.fromRank('').name, 'Argent');
        });
    });
    (0, node_test_1.describe)('difficulty progression', () => {
        (0, node_test_1.it)('has increasing difficulty properties', () => {
            const levels = [
                BotDifficulty_1.BotDifficulty.bronze,
                BotDifficulty_1.BotDifficulty.silver,
                BotDifficulty_1.BotDifficulty.gold,
                BotDifficulty_1.BotDifficulty.platinum,
            ];
            // forgetChancePerTurn should decrease (lower = better memory)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].forgetChancePerTurn <= levels[i - 1].forgetChancePerTurn, `forgetChancePerTurn should decrease: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
            // confusionOnSwap should decrease (lower = less mistakes)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].confusionOnSwap <= levels[i - 1].confusionOnSwap, `confusionOnSwap should decrease: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
            // dutchThreshold should decrease (lower = more aggressive Dutch calls)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].dutchThreshold <= levels[i - 1].dutchThreshold, `dutchThreshold should decrease: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
            // reactionSpeed should increase (higher = faster)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].reactionSpeed >= levels[i - 1].reactionSpeed, `reactionSpeed should increase: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
            // matchAccuracy should increase (higher = more accurate)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].matchAccuracy >= levels[i - 1].matchAccuracy, `matchAccuracy should increase: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
            // reactionMatchChance should increase (higher = more likely to match)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].reactionMatchChance >= levels[i - 1].reactionMatchChance, `reactionMatchChance should increase: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
            // keepCardThreshold should decrease (lower = keeps only better cards)
            for (let i = 1; i < levels.length; i++) {
                node_assert_1.default.ok(levels[i].keepCardThreshold <= levels[i - 1].keepCardThreshold, `keepCardThreshold should decrease: ${levels[i].name} vs ${levels[i - 1].name}`);
            }
        });
    });
});
