-module(enacl_SUITE).
-include_lib("common_test/include/ct.hrl").

-compile([export_all, nowarn_export_all]).

suite() ->
    [{timetrap, {seconds, 30}}].

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_suite(Config) ->
    application:ensure_all_started(enacl),
    Config.

end_per_suite(_Config) ->
    application:stop(enacl),
    ok.

init_per_testcase(x, Config) ->
    {ok, _} = dbg:tracer(),
    dbg:p(all, c),
    dbg:tpl(graphql_execute, lookup_field, '_', cx),
    Config;
init_per_testcase(_Case, Config) ->
    Config.

end_per_testcase(x, _Config) ->
    dbg:stop_clear(),
    ok;
end_per_testcase(_Case, _Config) ->
    ok.

groups() ->
    Neg = {negative, [shuffle, parallel],
      [generichash_basic_neg]},
    Pos = {positive, [shuffle, parallel],
                    [generichash_basic_pos,
                     generichash_chunked,
                     aead_xchacha20poly1305,
                     aead_chacha20poly1305,
                     pwhash,
                     sign]},

    [Neg, Pos].

all() ->
    [{group, negative},
     {group, positive}].

%% -- BASIC --------------------------------------
generichash_basic_neg(_Config) ->
    %% Negative generichash invocations
    Msg = <<"I've seen things you people wouldn't believe: attack ships on fire off the shoulder of Orion. "
            "I've watched C-beams glitter in the dark near the Tannhäuser Gate. "
            "All those... moments... will be lost... in time, like... tears... in rain">>,
    Key = <<"Hash Key 123456789">>,
    {error, invalid_hash_size} = enacl:generichash(9, Msg, Key),
    {error, invalid_hash_size} = enacl:generichash(65, Msg, Key),
    {error, invalid_key_size} = enacl:generichash(32, Msg, <<"Small">>),
    ok.

generichash_basic_pos(_Config) ->
    Msg = <<"I've seen things you people wouldn't believe: attack ships on fire off the shoulder of Orion. "
            "I've watched C-beams glitter in the dark near the Tannhäuser Gate. "
            "All those... moments... will be lost... in time, like... tears... in rain">>,
    Key = <<"Hash Key 123456789">>,
    {ok,<<189,104,45,187,170,229,212,4,121,43,137,74,241,173,181,77,
          67,211,133,70,196,6,128,97>>} = enacl:generichash(24, Msg, Key),
    ok.

generichash_chunked(_Config) ->
    Msg = <<"I've seen things you people wouldn't believe: attack ships on fire off the shoulder of Orion. "
            "I've watched C-beams glitter in the dark near the Tannhäuser Gate. "
            "All those... moments... will be lost... in time, like... tears... in rain">>,
    Key = <<"Hash Key 123456789">>,
    State = enacl:generichash_init(24, Key),
    State = generichash_chunked(State, Msg, 10000),
    Expected = <<46,49,32,18,13,186,182,105,106,122,253,139,89,176,169,141,
                 73,93,99,6,41,216,110,41>>,
    {ok, Expected} = enacl:generichash_final(State),
    ok.

generichash_chunked(State, _Msg, 0) -> State;
generichash_chunked(State, Msg, N) ->
    State2 = enacl:generichash_update(State, Msg),
    generichash_chunked(State2, Msg, N-1).

aead_xchacha20poly1305(_Config) ->
    NonceLen = enacl:aead_xchacha20poly1305_NONCEBYTES(),
    KLen = enacl:aead_xchacha20poly1305_KEYBYTES(),
    Key = binary:copy(<<"K">>, KLen),
    Msg = <<"test">>,
    AD = <<1,2,3,4,5,6>>,
    Nonce = binary:copy(<<"N">>, NonceLen),

    CipherText = enacl:aead_xchacha20poly1305_encrypt(Key, Nonce, AD, Msg),
    Msg = enacl:aead_xchacha20poly1305_decrypt(Key, Nonce, AD, CipherText),
    ok.

aead_chacha20poly1305(_Config) ->
    KLen = enacl:aead_chacha20poly1305_KEYBYTES(),
    Key = binary:copy(<<"K">>, KLen),
    Msg = <<"test">>,
    AD = <<1,2,3,4,5,6>>,
    Nonce = 1337,

    CipherText = enacl:aead_chacha20poly1305_encrypt(Key, Nonce, AD, Msg),
    Msg = enacl:aead_chacha20poly1305_decrypt(Key, Nonce, AD, CipherText),
    ok.

pwhash(_Config) ->
    PW = <<"XYZZY">>,
    Salt = <<"1234567890abcdef">>,
    Hash1 = <<164,75,127,151,168,101,55,77,48,77,240,204,64,20,43,23,88,
                 18,133,11,53,151,2,113,232,95,84,165,50,7,60,20>>,
    {ok, Hash1} = enacl:pwhash(PW, Salt),
    {ok, Str1} = enacl:pwhash_str(PW),
    true = enacl:pwhash_str_verify(Str1, PW),
    false = enacl:pwhash_str_verify(Str1, <<PW/binary, 1>>),
    ok.

sign(_Config) ->
    #{public := PK, secret := SK} = enacl:sign_keypair(),
    Msg = <<"Test">>,
    State = enacl:sign_init(),
    Create = sign_chunked(State, Msg, 10000),
    {ok, Signature} = enacl:sign_final_create(Create, SK),
    StateVerify = enacl:sign_init(),
    Verify = sign_chunked(StateVerify, Msg, 10000),
    ok = enacl:sign_final_verify(Verify, Signature, PK),
    ok.

sign_chunked(S, _M, 0) -> S;
sign_chunked(S, M, N) ->
    S2 = enacl:sign_update(S, M),
    sign_chunked(S2, M, N-1).

