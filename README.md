# FingerCounter iOS

Ứng dụng iOS dùng camera trước và Vision framework để:

- Nhận diện tối đa hai bàn tay và tô màu các đầu ngón.
- Phát hiện hitbox khi ngón cái chạm một trong bốn ngón còn lại.
- Hiển thị chấm xanh khi mắt/miệng mở và chấm đỏ khi đóng.
- Không đếm ngón tay và không vẽ mũi.

## Tạo IPA chưa ký bằng GitHub Actions

1. Tạo một repository GitHub mới.
2. Upload toàn bộ nội dung thư mục này lên repository.
3. Vào tab **Actions**, chọn **Build unsigned IPA**, bấm **Run workflow**.
4. Khi workflow hoàn tất, tải artifact `FingerCounter-unsigned-ipa`.
5. Tự ký file IPA bằng chứng chỉ/provisioning profile của bạn.

Workflow chạy trên macOS của GitHub Actions và dùng XcodeGen để tạo file Xcode project. Không cần commit file `.xcodeproj`.

## Chạy thử trên Mac

```bash
brew install xcodegen
xcodegen generate
open FingerCounter.xcodeproj
```

Trong Xcode, chọn Team và Bundle Identifier của bạn trước khi cài lên thiết bị thật. File IPA từ workflow chỉ là bản chưa ký, không cài trực tiếp được nếu chưa ký.
