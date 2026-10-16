<?php

namespace App\Filament\Central\Resources;

use App\Filament\Central\Resources\TenantResource\Pages;
use App\Filament\Central\Resources\TenantResource\RelationManagers\DomainsRelationManager;
use App\Filament\Central\Resources\TenantResource\RelationManagers\SubscriptionsRelationManager;
use App\Models\Central\Tenant;
use Filament\Forms;
use Filament\Actions\EditAction;
use Filament\Actions\DeleteAction;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Schemas\Schema;
use Filament\Resources\Resource;
use Filament\Tables;
use Filament\Tables\Table;

class TenantResource extends Resource
{
    protected static ?string $model = Tenant::class;
    protected static string|\BackedEnum|null $navigationIcon = 'heroicon-o-building-storefront';
    protected static string|\UnitEnum|null $navigationGroup = 'Platform';
    protected static ?string $navigationLabel = 'Tenants';

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('id')
                ->label('Tenant ID / slug')
                ->required()->maxLength(100)->alphaDash()->unique(ignoreRecord: true),
            Forms\Components\TextInput::make('store_name')->maxLength(255),
            Forms\Components\Toggle::make('is_active')
                ->label('Tenant active')
                ->default(true)
                ->required(),
            Forms\Components\Select::make('template_id')
                ->options(['BASIC' => 'BASIC', 'PRO' => 'PRO', 'ENTERPRISE' => 'ENTERPRISE'])
                ->required()->default('BASIC'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table->columns([
            Tables\Columns\TextColumn::make('id')->searchable()->sortable(),
            Tables\Columns\TextColumn::make('store_name')->searchable(),
            Tables\Columns\IconColumn::make('is_active')->boolean()->label('Active'),
            Tables\Columns\TextColumn::make('template_id')->badge(),
            Tables\Columns\TextColumn::make('domains.domain')->label('Domains')->listWithLineBreaks(),
            Tables\Columns\TextColumn::make('latestSubscription.plan')->label('Plan')->badge(),
            Tables\Columns\TextColumn::make('latestSubscription.status')->label('Subscription')->badge(),
            Tables\Columns\TextColumn::make('created_at')->dateTime()->sortable(),
        ])->actions([
            EditAction::make(),
            DeleteAction::make()->requiresConfirmation()
                ->modalDescription('Confirm tenant data-retention and database-destruction policy before deleting a production tenant.'),
        ])->bulkActions([
            BulkActionGroup::make([
                DeleteBulkAction::make()->requiresConfirmation(),
            ]),
        ]);
    }

    public static function getRelations(): array
    {
        return [DomainsRelationManager::class, SubscriptionsRelationManager::class];
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListTenants::route('/'),
            // Physical database provisioning uses an explicitly credentialed Artisan CLI only.
            'edit' => Pages\EditTenant::route('/{record}/edit'),
        ];
    }
}
