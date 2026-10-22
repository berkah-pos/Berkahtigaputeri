<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;
use LogicException;

class CoaAccount extends Model
{
    protected $connection = 'tenant';
    protected $table = 'coa_accounts';
    protected $primaryKey = 'code';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['code', 'name_id', 'name_en', 'account_type', 'normal_balance'];
    public static function booted(): void
    {
        static::saving(static function (): never {
            throw new LogicException('The approved chart of accounts is immutable.');
        });
        static::deleting(static function (): never {
            throw new LogicException('The approved chart of accounts is immutable.');
        });
    }
}
