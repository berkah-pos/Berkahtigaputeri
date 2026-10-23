<?php

namespace App\Models\Central;

use Laravel\Sanctum\PersonalAccessToken as SanctumPersonalAccessToken;

class PersonalAccessToken extends SanctumPersonalAccessToken
{
    protected $connection = 'central';
    protected $table = 'personal_access_tokens';
    protected $guarded = [];
}
