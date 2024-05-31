### `c.auth.get_token`
Given the correct email and password combination the server will send back a token that can be used to login as that user. This command must be performed over a secure connection, if it is attempted over an insecure connection the server will send back an error. If the password and email do not match a failure result is returned.

* email :: string
* password :: string

#### Success response
* token :: string

#### Example input/output
```json
{
  "cmd": "c.auth.get_token",
  "email": "email@email.com",
  "password": "*********"
}

{
  "cmd": "s.auth.get_token",
  "result": "success",
  "token": "long-string-of-digits-here"
}

{
  "cmd": "s.auth.get_token",
  "result": "failure",
  "reason": "reason for failure"
}
```

### `c.auth.login`
Performs user authentication via a token obtained from `c.auth.token`.
* token :: string
* lobby_name :: string
* lobby_version :: string

#### Success response
* user :: User

#### Example input/output
```json
{
  "cmd": "c.auth.login",
  "lobby_name": "Bar Lobby",
  "lobby_version": "1.3.2",
  "lobby_hash": "1234567890",
  "token": "long-string-of-digits-here"
}

{
  "cmd": "s.auth.login",
  "result": "success",
  "user": User
}

{
  "cmd": "s.auth.login",
  "result": "unverified",
  "agreement": "Multiline\nText\nBlob"
}

{
  "cmd": "s.auth.login",
  "result": "failure",
  "reason": "Invalid token"
}
```

### `c.auth.verify`
Confirms the accuracy of the user email address. Once successful the user will be marked as verified and the user logged in.
* token :: string
* verification_code :: string

#### Success response
* user :: User

#### Example input/output
```json
{
  "cmd": "c.auth.verify",
  "token": "long-string-of-digits-here",
  "code": "123456"
}

{
  "cmd": "s.auth.verify",
  "result": "success",
  "user": User
}

{
  "cmd": "s.auth.verify",
  "result": "failure",
  "reason": "bad code"
}
```

## `c.auth.disconnect`


#### Success response
The connection will be terminated, there will be no response.

#### Example input/output
```json
{
  "cmd": "c.auth.disconnect"
}
```

## `c.auth.register`
Requests the creation of a new user account on the server
* username :: string
* email :: email address
* password :: string (this will be stored in a hashe

#### Success response
You will receive a standard success response, if it fails you will receive a failure response. Once registered you can attempt to login though the server may require you to validate the account before the login can be successful.

#### Example input/output
```json
{
  "cmd": "c.auth.register",
  "username": "new_user_101",
  "email": "new_user@101.example"
  "password": "my_password"
}

{
  "cmd": "s.auth.register",
  "result": "success"
}

{
  "cmd": "s.auth.register",
  "result": "failure",
  "reason": "email already exists"
}
```

## TODO: `c.auth.migrate`
For users who do not have an email associated with their account (only possible when registering an account with the legacy protocol). Users will need to do this in order to login via Tachyon.
* username :: string
* password :: string
* email :: email address

#### Example input/output
```json
{
  "cmd": "c.auth.migrate",
  "username": "existing_user",
  "password": "my_password",
  "desired_email": "existing_user@101.example"
}

{
  "cmd": "s.auth.migrate",
  "result": "success"
}

{
  "cmd": "s.auth.migrate",
  "result": "failure",
  "reason": "A user with that email address already exists"
}

{
  "cmd": "s.auth.migrate",
  "result": "failure",
  "reason": "User does not exist"
}

{
  "cmd": "s.auth.migrate",
  "result": "failure",
  "reason": "Invalid password"
}
```
