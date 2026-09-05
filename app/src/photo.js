// 照片压缩。规格第八节：最大边 1600 px、JPEG 质量 82，与 Flutter 版一致。
// 不压缩直接存原图会把 IndexedDB 撑爆（规格第九节坑表）。

const MAX_EDGE = 1600;
const QUALITY = 0.82;

/**
 * 把用户选的图压成 JPEG Blob。
 * imageOrientation: 'from-image' 必须带 —— iPhone 拍的竖图靠 EXIF 记方向，
 * 不带这个参数画到 canvas 上会躺倒。
 */
export async function compress(file) {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const width = Math.round(bitmap.width * scale);
  const height = Math.round(bitmap.height * scale);

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  canvas.getContext('2d').drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error('图片压缩失败'))),
      'image/jpeg',
      QUALITY,
    );
  });
}
