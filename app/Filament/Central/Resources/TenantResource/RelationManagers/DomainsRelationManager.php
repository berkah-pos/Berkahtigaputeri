<?php

namespace App\Filament\Central\Resources\TenantResource\RelationManagers;

use Filament\Forms;
use Filament\Forms\Form;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Tables;
use Filament\Tables\Table;

class DomainsRelationManager extends RelationManager
{
    protected static string $relationship = 'domains';
    protected static ?string $title = 'Tenant domains';

    public function form(Form $form): Form
    {
        return $form->schema([
            Forms\Components\TextInput::make('domain')
                ->required()->maxLength(253)->unique(ignoreRecord: true)
                ->rule('regex:/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/i')
                ->helperText('Register only a platform-controlled and verified domain.'),
        ]);
    }

    public function table(Table $table): Table
    {
        return $table->columns([
            Tables\Columns\TextColumn::make('domain')->searchable(),
            Tables\Columns\TextColumn::make('created_at')->dateTime(),
        ])->headerActions([Tables\Actions\CreateAction::make()])
          ->actions([Tables\Actions\DeleteAction::make()->requiresConfirmation()]);
    }
}
