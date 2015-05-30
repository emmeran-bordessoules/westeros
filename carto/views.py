from django.shortcuts import render
from vote.models import scoreDep

def home(request):
	# score=scoreDep.objects.all()
	# for i in score: {'sd':sd}
		# sd+=scoreDep.objects.filter(=NumDep,i=VoteDep).max(ScoreVote)
	return render(request,'carto/carto.html',locals())
