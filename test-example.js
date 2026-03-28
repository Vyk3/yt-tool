// TDD 第二步：GREEN — 写最小化的实现让测试通过
function calculateSum(a, b) {
  return a + b;  // 最小实现，不多不少
}

function testCalculateSum() {
  const result = calculateSum(2, 3);
  console.assert(result === 5, `Expected 5 but got ${result}`);
  console.log("✅ Test passed: calculateSum(2, 3) = 5");
}

function testCalculateSumWithNegative() {
  const result = calculateSum(-1, 3);
  console.assert(result === 2, `Expected 2 but got ${result}`);
  console.log("✅ Test passed: calculateSum(-1, 3) = 2");
}

// 现在测试应该 pass
testCalculateSum();
testCalculateSumWithNegative();
