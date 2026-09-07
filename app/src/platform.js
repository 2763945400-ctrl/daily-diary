// 「现在跑在网页版还是 Capacitor 原生壳里」。
//
// 用协议判，而不是 import Capacitor.isNativePlatform() —— 只为一个布尔值
// 把 @capacitor/core 打进包里不划算（规格第九节点的是原生**能力调用**前必须判，
// 那些调用本来就要 import Capacitor，到时候顺手换过来即可）。
//
// ⚠️ 第 6 步接原生能力时改回 Capacitor.isNativePlatform()：
//    iOS 原生壳是 capacitor://localhost，这里判得对；
//    但**安卓原生壳是 http://localhost**，会被误判成网页版。
//    安卓在规格里是「预留后续扩展」，现在还没有，所以暂时不是问题。
export const IS_WEB = location.protocol === 'http:' || location.protocol === 'https:';
