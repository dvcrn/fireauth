ExUnit.start()

require Mox

Mox.defmock(Fireauth.FirebaseUpstreamMock, for: Fireauth.FirebaseUpstream)
Mox.defmock(Fireauth.TokenValidatorMock, for: Fireauth.TokenValidator)
Mox.defmock(Fireauth.SessionCookieValidatorMock, for: Fireauth.SessionCookieValidator)
