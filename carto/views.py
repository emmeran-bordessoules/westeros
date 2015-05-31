from django.shortcuts import render
from vote.models import scoreDep

def home(request):
	score=scoreDep.objects.order_by('-ScoreDep').order_by('NumDep')[:100]
	return render(request,'carto/carto.html',{'score':score})

