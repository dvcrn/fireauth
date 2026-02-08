defmodule Fireauth.FirebaseTest do
  use ExUnit.Case

  test "verify_id_token/2 rejects non-JWT tokens" do
    assert {:error, :invalid_token_format} = Fireauth.verify_id_token("nope")
    assert {:error, :invalid_token_format} = Fireauth.verify_id_token("a.b")
    assert {:error, :invalid_token_format} = Fireauth.verify_id_token("a.b.c.d")
  end
end
