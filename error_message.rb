module ErrorMessage
  FAILED_TO_DECODE_EMAIL =
    %{システムで本文を読み取れなかったため、メールは配送されませんでした。}
  EMPTY_EMAIL =
    %{件名または本文がなかったため、メールは配送されませんでした。}
  REPLY_EMAIL =
    %{件名が「Re:」で始まっており、メーリングリストへの返信と判定されたため、メールは配送されませんでした。}
  INVALID_MAILING_LIST =
    %{宛先のメーリングリストのアドレスが不正なため、メールは配送されませんでした。}
  UNEXPECTED_ERROR =
    %{システム内部でエラーが発生したため、メールは配送されませんでした。この件は技術管理部門へ報告されました。}
  ERROR_EMAIL_SUBJECT =
    %{[error] 配送エラー}
end
