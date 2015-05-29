from django.contrib import admin
from .models import *

class VoteAdmin(admin.ModelAdmin):
	list_display   = ('NomVote', 'Score',)
	
class VoteAdmin2(admin.ModelAdmin):
	list_display   = ('IPVotant',)
	
admin.site.register(Vote, VoteAdmin)
admin.site.register(Departement)
admin.site.register(scoreDep)
admin.site.register(Votant, VoteAdmin2)