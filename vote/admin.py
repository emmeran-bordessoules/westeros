from django.contrib import admin
from .models import *

class VoteAdmin(admin.ModelAdmin):
	list_display   = ('NomVote', 'Score',)
	
class VoteAdmin2(admin.ModelAdmin):
	list_display   = ('ipvotant',)
	
class VoteAdmin3(admin.ModelAdmin):
	list_display   = ('cit','auteur')
	
class VoteAdmin4(admin.ModelAdmin):
	list_display   = ('VoteDep','NumDep')
	
admin.site.register(Vote, VoteAdmin)
admin.site.register(Departement)
admin.site.register(scoreDep,VoteAdmin4)
admin.site.register(citation, VoteAdmin3)
admin.site.register(Votant, VoteAdmin2)