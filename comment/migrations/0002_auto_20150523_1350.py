# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
        ('comment', '0001_initial'),
    ]

    operations = [
        migrations.RenameField(
            model_name='comment',
            old_name='author',
            new_name='auteur',
        ),
        migrations.RenameField(
            model_name='comment',
            old_name='text',
            new_name='texte',
        ),
    ]
