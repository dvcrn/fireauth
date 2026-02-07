ExUnit.start()

Mox.defmock(Fireauth.FirebaseUpstreamMock, for: Fireauth.FirebaseUpstream)
Mox.defmock(Fireauth.TokenValidatorMock, for: Fireauth.TokenValidator)
