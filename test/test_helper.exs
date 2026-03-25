ExUnit.start()

require Mox

Mox.defmock(Fireauth.FirebaseUpstreamMock, for: Fireauth.FirebaseUpstream)
Mox.defmock(Fireauth.TokenValidatorMock, for: Fireauth.TokenValidator)
Mox.defmock(Fireauth.SessionCookieValidatorMock, for: Fireauth.SessionCookieValidator)
Mox.defmock(Fireauth.SessionCookieCreatorMock, for: Fireauth.SessionCookieCreator)
Mox.defmock(Fireauth.ServerAuthMock, for: Fireauth.ServerAuth)
Mox.defmock(Fireauth.EmailLinkSenderMock, for: Fireauth.EmailLinkSender)
